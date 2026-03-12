#!/usr/bin/env python3
"""
Credential Proxy Server for AWS Attack Simulation
Listens on localhost:8888 for stolen credentials and stores them in SSM Parameter Store
"""

import boto3
import json
import os
from http.server import HTTPServer, BaseHTTPRequestHandler

class CredHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/creds':
            try:
                # Read the credentials from the request
                content_length = int(self.headers['Content-Length'])
                creds_data = self.rfile.read(content_length).decode('utf-8')
                
                print(f"Received credentials data: {len(creds_data)} bytes", flush=True)
                
                # Get AWS region from environment
                aws_region = os.environ.get('AWS_REGION', 'us-west-2')
                
                # Write to SSM Parameter Store
                ssm = boto3.client('ssm', region_name=aws_region)
                ssm.put_parameter(
                    Name='/attack-simulation/stolen-credentials',
                    Value=creds_data,
                    Type='SecureString',
                    Overwrite=True
                )
                
                print(f"Successfully stored credentials in SSM Parameter Store", flush=True)
                
                # Send success response
                self.send_response(200)
                self.send_header('Content-Type', 'text/plain')
                self.end_headers()
                self.wfile.write(b'OK')
                
            except Exception as e:
                print(f"Error handling request: {e}")
                self.send_response(500)
                self.send_header('Content-Type', 'text/plain')
                self.end_headers()
                self.wfile.write(str(e).encode())
        else:
            # Handle other paths
            self.send_response(404)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'Not Found')

    def do_GET(self):
        """Health check endpoint"""
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'Credential proxy is running')
        else:
            self.send_response(404)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'Not Found')

    def log_message(self, format, *args):
        """Override to control logging"""
        # Only log important messages
        if args[1] != '200':
            print(f"{self.address_string()} - {format % args}")

def main():
    # Configuration
    host = '127.0.0.1'
    port = 8888
    
    # Create and start the server
    server = HTTPServer((host, port), CredHandler)
    print(f"Credential proxy server starting on {host}:{port}", flush=True)
    print("Waiting for stolen credentials...", flush=True)
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down credential proxy server", flush=True)
        server.shutdown()

if __name__ == "__main__":
    main()
