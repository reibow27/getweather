# Azure AI Agents function calling with Azure Functions

Azure AI Agents supports function calling, which allows you to describe the structure of functions to an Assistant and then return the functions that need to be called along with their arguments. This example shows how to use Azure Functions to process the function calls through queue messages in Azure Storage. You can see a complete working sample on https://github.com/Azure-Samples/azure-functions-ai-services-agent-python

### Supported models

To use all features of function calling including parallel functions, you need to use a model that was released after November 6, 2023.


## Define a function for your agent to call

Start by defining an Azure Function queue trigger function that will process function calls from the queue. 

```python
# Function to get the weather from an Azure Storage queue where the AI Agent will send function call information
# It returns the mock weather to an output queue with the correlation id for the AI Agent service to pick up the result of the function call
@app.function_name(name="GetWeather")
@app.queue_trigger(arg_name="msg", queue_name="input", connection="STORAGE_CONNECTION")  
def process_queue_message(msg: func.QueueMessage) -> None:
    logging.info('Python queue trigger function processed a queue item')

    # Queue to send message to
    queue_client = QueueClient(
        os.environ["STORAGE_CONNECTION__queueServiceUri"],
        queue_name="output",
        credential=DefaultAzureCredential(),
        message_encode_policy=BinaryBase64EncodePolicy(),
        message_decode_policy=BinaryBase64DecodePolicy()
    )

    # Get the content of the function call message
    messagepayload = json.loads(msg.get_body().decode('utf-8'))
    location = messagepayload['location']
    correlation_id = messagepayload['CorrelationId']

    # Send message to queue. Sends a mock message for the weather
    result_message = {
        'Value': 'Weather is 74 degrees and sunny in ' + location,
        'CorrelationId': correlation_id
    }
    queue_client.send_message(json.dumps(result_message).encode('utf-8'))

    logging.info(f"Sent message to output queue with message {result_message}")
```

---

## Create an AI project client and agent

In the sample below we create a client and an agent that has the tools definition for the Azure Function

```python
# Initialize the client and create agent for the tools Azure Functions that the agent can use

# Create a project client
project_client = AIProjectClient.from_connection_string(
    credential=DefaultAzureCredential(),
    conn_str=os.environ["PROJECT_CONNECTION_STRING"]
)

# Get the connection string for the storage account to send and receive the function calls to the queues
storage_connection_string = os.environ["STORAGE_CONNECTION__queueServiceUri"]

# Create an agent with the Azure Function tool to get the weather
agent = project_client.agents.create_agent(
    model="gpt-4o-mini",
    name="azure-function-agent-get-weather",
    instructions="You are a helpful support agent. Answer the user's questions to the best of your ability.",
    headers={"x-ms-enable-preview": "true"},
    tools=[
        {
            "type": "azure_function",
            "azure_function": {
                "function": {
                    "name": "GetWeather",
                    "description": "Get the weather in a location.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "location": {"type": "string", "description": "The location to look up."}
                        },
                        "required": ["location"]
                    }
                },
                "input_binding": {
                    "type": "storage_queue",
                    "storage_queue": {
                        "queue_service_uri": storage_connection_string,
                        "queue_name": "input"
                    }
                },
                "output_binding": {
                    "type": "storage_queue",
                    "storage_queue": {
                        "queue_service_uri": storage_connection_string,
                        "queue_name": "output"
                    }
                }
            }
        }
    ],
)
```

---

## Create a thread for the agent

```python
# Create a thread
thread = project_client.agents.create_thread()
print(f"Created thread, thread ID: {thread.id}")
```

---

## Create a run and check the output

```python
# Send the prompt to the agent
message = project_client.agents.create_message(
    thread_id=thread.id,
    role="user",
    content="What is the weather in Seattle, WA?",
)
print(f"Created message, message ID: {message.id}")

# Run the agent
run = project_client.agents.create_run(thread_id=thread.id, agent_id=agent.id)
# Monitor and process the run status. The function call will be placed on the input queue by the Agent service for the Azure Function to pick up when requires_action is returned
# The agent will then pick up the message that the queue trigger function returned in the output queue and complete
while run.status in ["queued", "in_progress", "requires_action"]:
    time.sleep(1)
    run = project_client.agents.get_run(thread_id=thread.id, run_id=run.id)

    if run.status not in ["queued", "in_progress", "requires_action"]:
        break

print(f"Run finished with status: {run.status}")
```

---

### Get the result of the run and print out

```python
# Get messages from the assistant thread
messages = project_client.agents.list_messages(thread_id=thread.id)
print(f"Messages: {messages}")

# Get the last message from the agent
last_msg = None
for data_point in messages.data:
    if data_point.role == "assistant":
        last_msg = data_point.content[-1]
        print(f"Last Message: {last_msg.text.value}")
        break

# Delete the agent once done
project_client.agents.delete_agent(agent.id)
print("Deleted agent")
```
