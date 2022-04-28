import json
import os
import requests


def lacework_reporter (event, context):
   senddata = {}
   senddata["customer_id"] = os.environ['CUSTOMER_KEY']
   senddata["log_type"] = "SOME_LOG"
   senddata["entries"] = [json.loads(event['body'])]

   x = requests.post(os.environ['GC_URL'], data=json.dumps(senddata))
   return { 'statusCode' : 200 }
