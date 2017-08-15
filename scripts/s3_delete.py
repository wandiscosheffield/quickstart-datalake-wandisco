#!/usr/bin/python

import time
import boto3
import logging
import cfnresponse

logger = logging.getLogger()
logger.setLevel(logging.INFO)

CFN_REQUEST_TYPE = "RequestType"
CFN_RESOURCE_PROPERTIES = "ResourceProperties"
SUCCEEDED = "SUCCEEDED"
FAILED = "FAILED"
CANCELLED = "CANCELLED"


class S3Resource(object):
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
        cfnresponse.send(event, context, cfnresponse.SUCCESS, {})

    def update(self, event, context):
        cfnresponse.send(event, context, cfnresponse.SUCCESS, {})

    def delete(self, event, context):
        props = event[CFN_RESOURCE_PROPERTIES]
        tmp_bucket = props["Bucket"]

        s3 = boto3.resource('s3')
        bucket = s3.Bucket(tmp_bucket)
        bucket.objects.all().delete()

        cfnresponse.send(event, context, cfnresponse.SUCCESS, {})

handler = S3Resource()

