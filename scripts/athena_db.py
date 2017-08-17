#!/usr/bin/python

import time
import boto3
import logging
import cfnresponse
import re

logger = logging.getLogger()
logger.setLevel(logging.INFO)
athena = boto3.client('athena')

CFN_REQUEST_TYPE = "RequestType"
CFN_RESOURCE_PROPERTIES = "ResourceProperties"
SUCCEEDED = "SUCCEEDED"
FAILED = "FAILED"
CANCELLED = "CANCELLED"


class AthenaCloudFormationResource(object):
    def __init__(self):
        self._delegate = {
            'Create': self.create,
            'Update': self.update,
            'Delete': self.delete
        }

    def __call__(self, event, context):
        try:
            request = event[CFN_REQUEST_TYPE]
            self._delegate[request](event, context)
        except Exception as e:
            logger.exception("Unable to complete CFN request {}".format(str(e)))
            cfnresponse.send(event, context, cfnresponse.FAILED, {})

    def create(self, event, context):
        """
        Create Athena resources with given name. Will write to the S3 buck in a folder.
        :param event: Lambda event data from CFN template.
        :param context: Lambda context
        :return: Response data with table information.
        """
        logger.info("Got Event: {}".format(event))
        props = event[CFN_RESOURCE_PROPERTIES]

        tmp_bucket = props["AthenaBucket"]
        database_name = re.sub("[^A-Za-z0-9]+", "_", props["DatabaseName"])

        database_result = 's3://{}'.format(tmp_bucket)

        result = AthenaCloudFormationResource.__create_db(database_name, database_result)
        if result:
            cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
        else:
            cfnresponse.send(event, context, cfnresponse.FAILED, {})

    def update(self, event, context):
        cfnresponse.send(event, context, cfnresponse.SUCCESS, {})

    def delete(self, event, context):
        """
        Delete Athena resources with given name. Will delete all content created in S3 bucket.
        :param event:
        :param context:
        :return:
        """

        props = event[CFN_RESOURCE_PROPERTIES]
        tmp_bucket = props["AthenaBucket"]
        database_name = re.sub("[^A-Za-z0-9]+", "_", props["DatabaseName"])

        database_result = 's3://{}'.format(tmp_bucket)

        if AthenaCloudFormationResource.__drop_db(database_name, database_result):
            s3 = boto3.resource('s3')
            bucket = s3.Bucket(tmp_bucket)
            bucket.objects.all().delete()

            cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
        else:
            cfnresponse.send(event, context, cfnresponse.FAILED, {})

    @staticmethod
    def __create_db(name, database_result):
        query = 'CREATE DATABASE IF NOT EXISTS {} LOCATION \'{}/\''.format(name, database_result)
        logger.info(
            "Execute: {}".format(query))
        response = athena.start_query_execution(
            QueryString=query,
            ResultConfiguration={
                'OutputLocation': '{}/output'.format(database_result)
            }
        )
        logger.info("ExecuteResponse: {}".format(response))

        return AthenaCloudFormationResource.__check_state(response['QueryExecutionId'])

    @staticmethod
    def __drop_db(name, database_result):
        response = athena.start_query_execution(
            QueryString='DROP DATABASE {}'.format(name),
            ResultConfiguration={
                'OutputLocation': '{}/output'.format(database_result)
            }
        )
        logger.info("ExecuteResponse: {}".format(response))

        return AthenaCloudFormationResource.__check_state(response['QueryExecutionId'])

    @staticmethod
    def __check_state(execution_id):
        running = True
        while running:
            execution_response = athena.get_query_execution(
                QueryExecutionId=execution_id
            )
            logger.info("QueryResponse: {}".format(execution_response))
            execution_state = execution_response['QueryExecution']['Status']['State']
            if execution_state in [SUCCEEDED]:
                return True
            elif execution_state in [FAILED, CANCELLED]:
                return False
            else:
                time.sleep(1)

handler = AthenaCloudFormationResource()
