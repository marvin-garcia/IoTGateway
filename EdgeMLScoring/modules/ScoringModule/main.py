# Copyright (c) Microsoft. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for
# full license information.

import os
import sys
import time
import json
import asyncio
import requests
from six.moves import input
import threading
from azure.iot.device.aio import IoTHubModuleClient

# Retrieve ML module scoring endpoint from env vars
scoring_endpoint = os.environ['SCORING_ENDPOINT']

# global counters
TWIN_CALLBACKS = 0
RECEIVED_MESSAGES = 0

async def main():
    try:
        if not sys.version >= "3.5.3":
            raise Exception( "The sample requires python 3.5.3+. Current version of Python: %s" % sys.version )
        print ( "IoT Hub Client for Python" )

        # The client object is used to interact with your Azure IoT hub.
        module_client = IoTHubModuleClient.create_from_edge_environment()

        # connect the client.
        await module_client.connect()

        # Define behavior for receiving an input message on input1
        # Because this is a filter module, we forward this message to the "output1" queue.
        async def input1_listener(module_client):
            global RECEIVED_MESSAGES
            while True:
                try:
                    input_message = await module_client.receive_message_on_input("input1")  # blocking call
                    message = input_message.data
                    size = len(message)
                    # message_text = message.decode('utf-8')
                    message_text = message
                    # print ( "    Data: <<<%s>>> & Size=%d" % (message_text, size) )
                    RECEIVED_MESSAGES += 1
                    print ( "    Total messages received: %d" % RECEIVED_MESSAGES )
                    data = json.loads(message_text)
                    
                    print ( "Calling ML module %s" % scoring_endpoint)
                    response = requests.post(url = scoring_endpoint, json = data)
                    print("ML module response's status code was %s" % response.status_code)

                    if (response.status_code == 200):
                        print ( "ML module score is")
                        print(response.json())
                        print ( "Sending score result to IoT Hub")
                        await module_client.send_message_to_output(json.dumps(response.json()), "output1")
                except Exception as ex:
                    print ( "Unexpected error in input1_listener: %s" % ex )

        # twin_patch_listener is invoked when the module twin's desired properties are updated.
        async def twin_patch_listener(module_client):
            global TWIN_CALLBACKS
            while True:
                try:
                    data = await module_client.receive_twin_desired_properties_patch()  # blocking call
                    print( "The data in the desired properties patch was: %s" % data)
                    TWIN_CALLBACKS += 1
                    print ( "Total calls confirmed: %d\n" % TWIN_CALLBACKS )
                except Exception as ex:
                    print ( "Unexpected error in twin_patch_listener: %s" % ex )

        # define behavior for halting the application
        def stdin_listener():
            while True:
                try:
                    selection = input("Press Q to quit\n")
                    if selection == "Q" or selection == "q":
                        print("Quitting...")
                        break
                except:
                    time.sleep(10)

        # Schedule task for C2D Listener
        listeners = asyncio.gather(input1_listener(module_client), twin_patch_listener(module_client))

        print ( "The sample is now waiting for messages. ")

        # Run the stdin listener in the event loop
        loop = asyncio.get_event_loop()
        user_finished = loop.run_in_executor(None, stdin_listener)

        # Wait for user to indicate they are done listening for messages
        await user_finished

        # Cancel listening
        listeners.cancel()
        print("Canceling event listeners")

        # Finally, disconnect
        await module_client.disconnect()
        print("disconnecting module client from IoT hub")

    except Exception as e:
        print ( "Unexpected error %s " % e )
        raise

if __name__ == "__main__":
    # loop = asyncio.get_event_loop()
    # loop.run_until_complete(main())
    # loop.close()

    # If using Python 3.7 or above, you can use following code instead:
    asyncio.run(main())