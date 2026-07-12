from flask import Flask, jsonify
import os

app = Flask(__name__)

@app.get("/")
def home():
    return jsonify({
        "app": os.getenv("APP_NAME", "demo-app"),
        "env": os.getenv("ENV", "dev"),
        "version": os.getenv("VERSION", "0.1.0"),
        "message": "Hello from Helm demo app"
    })

@app.get("/health")
def health():
    return jsonify({"status": "ok"})
    
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
