import json
from random import randint
from flask import Flask, request, Response

app = Flask(__name__)

@app.route('/health', methods=[ 'GET', 'POST' ])
def health():
    return { "status": "healthy" }

@app.route('/score', methods=[ 'POST' ])
def score():
    data = json.loads(request.data)
    print(data)
    if not data or data == {}:
        return "payload cannot be empty", 400

    score = randint(0, 100) / 100
    return { "score": score }

if __name__ == '__main__':
    print("Starting application. Debug=True, host=0.0.0.0")
    app.run(debug=True,host='0.0.0.0')