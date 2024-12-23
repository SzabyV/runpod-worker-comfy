import runpod
from runpod.serverless.utils import rp_upload
import json
import urllib.request
import urllib.parse
import time
import os
import requests
import base64
from io import BytesIO
import shutil
from pathlib import Path
from math import pow, ceil

size_of_input_images = 0

# Time to wait between API check attempts in milliseconds
COMFY_API_AVAILABLE_INTERVAL_MS = 50
# Maximum number of API check attempts
COMFY_API_AVAILABLE_MAX_RETRIES = 500
# Time to wait between poll attempts in milliseconds
COMFY_POLLING_INTERVAL_MS = int(os.environ.get("COMFY_POLLING_INTERVAL_MS", 250))
# Maximum number of poll attempts
COMFY_POLLING_MAX_RETRIES = int(os.environ.get("COMFY_POLLING_MAX_RETRIES", 500))
# Host where ComfyUI is running
COMFY_HOST = "127.0.0.1:8188"
# Enforce a clean state after each job is done
# see https://docs.runpod.io/docs/handler-additional-controls#refresh-worker
REFRESH_WORKER = os.environ.get("REFRESH_WORKER", "false").lower() == "true"


def validate_input(job_input):
    """
    Validates the input for the handler function.

    Args:
        job_input (dict): The input data to validate.

    Returns:
        tuple: A tuple containing the validated data and an error message, if any.
               The structure is (validated_data, error_message).
    """
    # Validate if job_input is provided
    if job_input is None:
        return None, "Please provide input"

    # Check if input is a string and try to parse it as JSON
    if isinstance(job_input, str):
        try:
            job_input = json.loads(job_input)
        except json.JSONDecodeError:
            return None, "Invalid JSON format in input"

    # Validate 'workflow' in input
    workflow = job_input.get("workflow")
    if workflow is None:
        return None, "Missing 'workflow' parameter"

    # Validate 'images' in input, if provided
    images = job_input.get("images")
    if images is not None:
        if not isinstance(images, list) or not all(
            "name" in image and "image" in image for image in images
        ):
            return (
                None,
                "'images' must be a list of objects with 'name' and 'image' keys",
            )

    # Return validated data and no error
    return {"workflow": workflow, "images": images}, None


def check_server(url, retries=500, delay=50):
    """
    Check if a server is reachable via HTTP GET request

    Args:
    - url (str): The URL to check
    - retries (int, optional): The number of times to attempt connecting to the server. Default is 50
    - delay (int, optional): The time in milliseconds to wait between retries. Default is 500

    Returns:
    bool: True if the server is reachable within the given number of retries, otherwise False
    """

    for i in range(retries):
        try:
            response = requests.get(url)

            # If the response status code is 200, the server is up and running
            if response.status_code == 200:
                print(f"runpod-worker-comfy - API is reachable")
                return True
        except requests.RequestException as e:
            # If an exception occurs, the server may not be ready
            pass

        # Wait for the specified delay before retrying
        time.sleep(delay / 1000)

    print(
        f"runpod-worker-comfy - Failed to connect to server at {url} after {retries} attempts."
    )
    return False


def upload_images(images):
    global size_of_input_images
    """
    Upload a list of base64 encoded images to the ComfyUI server using the /upload/image endpoint.

    Args:
        images (list): A list of dictionaries, each containing the 'name' of the image and the 'image' as a base64 encoded string.
        server_address (str): The address of the ComfyUI server.

    Returns:
        list: A list of responses from the server for each image upload.
    """
    if not images:
        return {"status": "success", "message": "No images to upload", "details": []}

    responses = []
    upload_errors = []
    image_list = []

    print(f"runpod-worker-comfy - image(s) upload")

    for image in images:
        name = image["name"]
        image_data = image["image"]
        
        blob = base64.b64decode(image_data)
        # Prepare the form data
        files = {
            "image": (name, BytesIO(blob), "image/png"),
            "overwrite": (None, "true"),
        }

        # POST request to upload the image
        response = requests.post(f"http://{COMFY_HOST}/upload/image", files=files)
        if response.status_code != 200:
            upload_errors.append(f"Error uploading {name}: {response.text}")
        else:
            responses.append(f"Successfully uploaded {name}")
            image_list.append(blob)

    size_of_input_images= calculate_size_of_images(images)
    print(f"Size of Input images is: {size_of_input_images}")

    if upload_errors:
        print(f"runpod-worker-comfy - image(s) upload with errors")
        return {
            "status": "error",
            "message": "Some images failed to upload",
            "details": upload_errors,
        }

    print(f"runpod-worker-comfy - image(s) upload complete")
    return {
        "status": "success",
        "message": "All images uploaded successfully",
        "details": responses,
    }


def queue_workflow(workflow):
    """
    Queue a workflow to be processed by ComfyUI

    Args:
        workflow (dict): A dictionary containing the workflow to be processed

    Returns:
        dict: The JSON response from ComfyUI after processing the workflow
    """

    # The top level element "prompt" is required by ComfyUI
    data = json.dumps({"prompt": workflow}).encode("utf-8")

    req = urllib.request.Request(f"http://{COMFY_HOST}/prompt", data=data)
    return json.loads(urllib.request.urlopen(req).read())


def get_history(prompt_id):
    """
    Retrieve the history of a given prompt using its ID

    Args:
        prompt_id (str): The ID of the prompt whose history is to be retrieved

    Returns:
        dict: The history of the prompt, containing all the processing steps and results
    """
    with urllib.request.urlopen(f"http://{COMFY_HOST}/history/{prompt_id}") as response:
        return json.loads(response.read())


def base64_encode(img_path):
    """
    Returns base64 encoded image.

    Args:
        img_path (str): The path to the image

    Returns:
        str: The base64 encoded image
    """
    with open(img_path, "rb") as image_file:
        encoded_string = base64.b64encode(image_file.read()).decode("utf-8")
        return f"{encoded_string}"


def process_output_images(outputs, job_id):
    """
    This function takes the "outputs" from image generation and the job ID,
    then determines the correct way to return the image, either as a direct URL
    to an AWS S3 bucket or as a base64 encoded string, depending on the
    environment configuration.

    Args:
        outputs (dict): A dictionary containing the outputs from image generation,
                        typically includes node IDs and their respective output data.
        job_id (str): The unique identifier for the job.

    Returns:
        dict: A dictionary with the status ('success' or 'error') and the message,
              which is either the URL to the image in the AWS S3 bucket or a base64
              encoded string of the image. In case of error, the message details the issue.

    The function works as follows:
    - It first determines the output path for the images from an environment variable,
      defaulting to "/comfyui/output" if not set.
    - It then iterates through the outputs to find the filenames of the generated images.
    - After confirming the existence of the image in the output folder, it checks if the
      AWS S3 bucket is configured via the BUCKET_ENDPOINT_URL environment variable.
    - If AWS S3 is configured, it uploads the image to the bucket and returns the URL.
    - If AWS S3 is not configured, it encodes the image in base64 and returns the string.
    - If the image file does not exist in the output folder, it returns an error status
      with a message indicating the missing image file.
    """

    # The path where ComfyUI stores the generated images
    COMFY_OUTPUT_PATH = os.environ.get("COMFY_OUTPUT_PATH", "/comfyui/output")

    output_images = {}

    for node_id, node_output in outputs.items():
        if "images" in node_output:
            for image in node_output["images"]:
                output_images = os.path.join(image["subfolder"], image["filename"])

    print(f"runpod-worker-comfy - image generation is done - single image method")

    # expected image output folder
    local_image_path = f"{COMFY_OUTPUT_PATH}/{output_images}"

    print(f"runpod-worker-comfy - {local_image_path}")

    # The image is in the output folder
    if os.path.exists(local_image_path):
        if os.environ.get("BUCKET_ENDPOINT_URL", False):
            # URL to image in AWS S3
            image_url = rp_upload.upload_image(job_id, local_image_path)
            image_json = {
                            "name": image["filename"],
                            "image": image_url
                            }
            print(
                "runpod-worker-comfy - the image was generated and uploaded to AWS S3"
            )
            return {
                "status": "success",
                "message": {"results": image_json},
            }
        else:
            # base64 image
            image = base64_encode(local_image_path)
            print(
                "runpod-worker-comfy - the image was generated and converted to base64"
            )
            return {
                "status": "success",
                "message": image,
            }

        
    else:
        print("runpod-worker-comfy - the image does not exist in the output folder")
        return {
            "status": "error",
            "message": f"the image does not exist in the specified output folder: {local_image_path}",
        }
    
def resize_image(image, wished_length):
            
    width, height = image.size
    if(width > wished_length) or (height > wished_length):
        proportion = width/height
        #portrait
        if(proportion < 1):
            new_height = wished_length
            new_width = round(proportion*new_height)
        else:
            new_width = wished_length
            new_height = round(new_width/proportion)
        
        new_image = image.resize((new_width, new_height))
        return new_image

def optimize_input_images_for_online_rendering(images,wished_length = 1024):

    for image in images:
        if(images is not None):
            images = resize_image(image, wished_length)
    
def calculate_size_of_images(images):
    import base64
    size_of_images = 0
    for image in images:
        if(image is not None):
            
            #img = image

            # Save the image to an in-memory buffer as PNG
            buffer = BytesIO()
            image.save(buffer, format="PNG")

            # Get the size in bytes
            size_in_bytes = len(buffer.getvalue())
            
            encoded_size = ceil(size_in_bytes / 3) * 4
           
            size_of_images +=encoded_size
            
    return size_of_images

def process_output_images_list(outputs, job_id, save_to_storage=None):
    """
    Processes the outputs to return a list of generated images and optionally saves them
    to RunPod's storage drive if the `save_to_storage` parameter is provided.

    Args:
        outputs (dict): Outputs from the image generation.
        job_id (str): Unique job identifier.
        save_to_storage (str): Directory path to save the images on RunPod's storage. Defaults to None.

    Returns:
        dict: A dictionary containing the status ('success' or 'error') and the results,
              which include either the Base64 encoded content or URLs to images.
    """
    COMFY_OUTPUT_PATH = os.environ.get("COMFY_OUTPUT_PATH", "/comfyui/output")

    image_list = []
    errors = []
    images = []

    print("List of Images method - outputs:")


    #for node_id, node_output in outputs.items():
        #print(node_output)
        #if "images" in node_output:
            #images.append(node_output["images"])

    #size_of_output_images = calculate_size_of_images(images)
    #print(f"Size of Images is: {size_of_output_images}")

    #if(size_of_input_images + size_of_output_images >= 19.5 * pow(10,6)):
        #print("Returned images might be too large to be able to receive them without AWS S3")
        
    for node_id, node_output in outputs.items():
        if "images" in node_output:
            for image in node_output["images"]:
                local_image_path = os.path.join(
                    COMFY_OUTPUT_PATH, image["subfolder"], image["filename"]
                )

                print(f"runpod-worker-comfy - image generation is done - list of images method")

                if os.path.exists(local_image_path):
                    # Determine the return type: S3 URL or Base64 string
                    if os.environ.get("BUCKET_ENDPOINT_URL", False):
                        # Upload to AWS S3                        
                        image_url = rp_upload.upload_image(job_id, local_image_path)
                        image_json = {
                            "name": image["filename"],
                            "image": image_url
                            }
                        image_list.append(image_json)
                    else:
                        # Encode in Base64
                        base64_image = base64_encode(local_image_path)
                        image_json = {
                            "name": image["filename"],
                            "image": base64_image
                            }
                        image_list.append(image_json)

                    # Save to RunPod storage if requested
                    #if save_to_storage:
                        #storage_path = os.path.join(save_to_storage, image["filename"])
                        #Path(save_to_storage).mkdir(parents=True, exist_ok=True)
                        #shutil.copy2(local_image_path, storage_path)
                        #print(f"Saved image to RunPod storage: {storage_path}")

                else:
                    # Log the error if the file doesn't exist
                    error_message = f"Image not found: {local_image_path}"
                    errors.append(error_message)
                    print(error_message)

    if image_list:
        return {
            "status": "success",
            "message": {"results": image_list} ,
            "errors": errors if errors else None,
        }
    else:
        return {
            "status": "error",
            "message": "No images were successfully processed.",
            "errors": errors,
        }

def handler(job):
    """
    The main function that handles a job of generating an image.

    This function validates the input, sends a prompt to ComfyUI for processing,
    polls ComfyUI for result, and retrieves generated images.

    Args:
        job (dict): A dictionary containing job details and input parameters.

    Returns:
        dict: A dictionary containing either an error message or a success status with generated images.
    """
    job_input = job["input"]

    # Make sure that the input is valid
    validated_data, error_message = validate_input(job_input)
    if error_message:
        return {"error": error_message}

    # Extract validated data
    workflow = validated_data["workflow"]
    images = validated_data.get("images")

    # Make sure that the ComfyUI API is available
    check_server(
        f"http://{COMFY_HOST}",
        COMFY_API_AVAILABLE_MAX_RETRIES,
        COMFY_API_AVAILABLE_INTERVAL_MS,
    )

    # Upload images if they exist
    upload_result = upload_images(images)

    if upload_result["status"] == "error":
        return upload_result

    # Queue the workflow
    try:
        queued_workflow = queue_workflow(workflow)
        prompt_id = queued_workflow["prompt_id"]
        print(f"runpod-worker-comfy - queued workflow with ID {prompt_id}")
    except Exception as e:
        return {"error": f"Error queuing workflow: {str(e)}"}

    # Poll for completion
    print(f"runpod-worker-comfy - wait until image generation is complete")
    retries = 0
    try:
        while retries < COMFY_POLLING_MAX_RETRIES:
            history = get_history(prompt_id)

            # Exit the loop if we have found the history
            if prompt_id in history and history[prompt_id].get("outputs"):
                break
            else:
                # Wait before trying again
                time.sleep(COMFY_POLLING_INTERVAL_MS / 1000)
                retries += 1
        else:
            return {"error": "Max retries reached while waiting for image generation"}
    except Exception as e:
        return {"error": f"Error waiting for image generation: {str(e)}"}
    
    try:
        # Get the generated image and return it as URL in an AWS bucket or as base64
        images_result = process_output_images_list(history[prompt_id].get("outputs"), job["id"])
    except Exception as e:
        print(f"Error while saving list of images: {str(e)}")
        # Get the generated image and return it as URL in an AWS bucket or as base64
        images_result = process_output_images(history[prompt_id].get("outputs"), job["id"])
    print("Just about to print the results (response):")
    
    result = {**images_result, "refresh_worker": REFRESH_WORKER}
    print(result)

    return result


# Start the handler only if this script is run directly
if __name__ == "__main__":
    runpod.serverless.start({"handler": handler})
