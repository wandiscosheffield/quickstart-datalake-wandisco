#!/usr/bin/python

import time
import boto3
import logging
import cfnresponse

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
        logger.info("Got Event: {}".format(event))
        props = event[CFN_RESOURCE_PROPERTIES]

        tmp_bucket = props["AthenaBucket"]
        sync_bucket = props["SyncBucket"]
        database_name = props["DatabaseName"]

        database_result = 's3://{}'.format(tmp_bucket)
        sync_result = 's3://{}'.format(sync_bucket)

        result = AthenaCloudFormationResource.__create_taxi_table('{}.taxi_tripdata'.format(database_name),
                                                                  sync_result, database_result)
        if result:
            cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
        else:
            cfnresponse.send(event, context, cfnresponse.FAILED, {})

    def update(self, event, context):
        cfnresponse.send(event, context, cfnresponse.SUCCESS, {})

    def delete(self, event, context):
        props = event[CFN_RESOURCE_PROPERTIES]
        tmp_bucket = props["AthenaBucket"]
        database_name = props["DatabaseName"]

        database_result = 's3://{}'.format(tmp_bucket)

        if AthenaCloudFormationResource.__drop_table('{}.taxi_tripdata'.format(database_name), database_result):
            cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
        else:
            cfnresponse.send(event, context, cfnresponse.FAILED, {})

    @staticmethod
    def __create_taxi_table(name, sync_result, database_result):
        query_string = """
            CREATE EXTERNAL TABLE IF NOT EXISTS {} (
                 vendor_id TINYINT,
                 lpep_pickup_datetime TIMESTAMP,
                 lpep_dropoff_datetime TIMESTAMP,
                 store_and_fwd_flag VARCHAR(1),
                 rate_code_id TINYINT,
                 pickup_longitude DOUBLE,
                 pickup_latitude DOUBLE,
                 dropoff_longitude DOUBLE,
                 dropoff_latitude DOUBLE,
                 passenger_count TINYINT,
                 trip_distance FLOAT,
                 fare_amount DECIMAL(10,2),
                 extra DECIMAL(10,2),
                 mta_tax DECIMAL(10,2),
                 tip_amount DECIMAL(10,2),
                 tolls_amount DECIMAL(10,2),
                 ehail_fee DECIMAL(10,2),
                 improvement_surcharge DECIMAL(10,2),
                 total_amount DECIMAL(10,2),
                 payment_type TINYINT,
                 trip_type TINYINT 
            ) 
            ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
            STORED AS TEXTFILE 
            LOCATION '{}/'
        """.format(name, sync_result)
        response = athena.start_query_execution(
            QueryString=query_string,
            ResultConfiguration={
                'OutputLocation': '{}/output'.format(database_result)
            }
        )
        logger.info(query_string)
        logger.info("ExecuteResponse: {}".format(response))

        return AthenaCloudFormationResource.__check_state(response['QueryExecutionId'])

    @staticmethod
    def __drop_table(name, database_result):
        response = athena.start_query_execution(
            QueryString='DROP TABLE {}'.format(name),
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



