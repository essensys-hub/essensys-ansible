#!/usr/bin/env python3
"""
MQTT Debug Interface Web
Interface web pour déboguer et monitorer MQTT
"""
import json
import logging
import threading
import time
from collections import deque
from datetime import datetime

import paho.mqtt.client as mqtt
from flask import Flask, render_template_string, request, jsonify
from flask_socketio import SocketIO, emit

# Configuration
MQTT_BROKER = "localhost"
MQTT_PORT = 1883
MQTT_USERNAME = "essensys"
MQTT_PASSWORD = None  # Will be read from config file
WEB_PORT = 9091
DEBUG = False
CONFIG_FILE = "/opt/essensys/mqtt_debug_config.json"

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Flask app
app = Flask(__name__)
app.config['SECRET_KEY'] = 'essensys-mqtt-debug-secret'
socketio = SocketIO(app, cors_allowed_origins="*")

# Message storage
messages = deque(maxlen=1000)  # Keep last 1000 messages
subscribed_topics = set()
mqtt_client = None
mqtt_connected = False
stats = {
    "messages_received": 0,
    "messages_published": 0,
    "topics_count": 0,
    "connected": False,
    "last_message_time": None
}


def load_mqtt_config():
    """Load MQTT config from config file or environment"""
    global MQTT_PASSWORD, MQTT_USERNAME, MQTT_BROKER, MQTT_PORT
    try:
        import os
        import json
        
        # Try to read from config file
        if os.path.exists(CONFIG_FILE):
            with open(CONFIG_FILE, 'r') as f:
                config = json.load(f)
                MQTT_PASSWORD = config.get('password', MQTT_PASSWORD)
                MQTT_USERNAME = config.get('username', MQTT_USERNAME)
                MQTT_BROKER = config.get('broker', MQTT_BROKER)
                MQTT_PORT = config.get('port', MQTT_PORT)
                logger.info(f"Loaded MQTT config from {CONFIG_FILE}")
        
        # Fallback to environment variables
        if not MQTT_PASSWORD:
            MQTT_PASSWORD = os.getenv("MQTT_PASSWORD", "essensys")
        
        if not MQTT_PASSWORD:
            logger.error("MQTT password not configured!")
            
    except Exception as e:
        logger.warning(f"Could not load MQTT config: {e}")
        # Use defaults
        if not MQTT_PASSWORD:
            MQTT_PASSWORD = os.getenv("MQTT_PASSWORD", "essensys")


def on_connect(client, userdata, flags, rc):
    """MQTT connection callback"""
    global mqtt_connected
    if rc == 0:
        mqtt_connected = True
        stats["connected"] = True
        logger.info("Connected to MQTT broker")
        socketio.emit('mqtt_status', {'connected': True})
        # Subscribe to all Essensys topics
        client.subscribe("essensys/#")
        client.subscribe("homeassistant/#")
    else:
        mqtt_connected = False
        stats["connected"] = False
        logger.error(f"Failed to connect to MQTT broker: {rc}")
        socketio.emit('mqtt_status', {'connected': False})


def on_disconnect(client, userdata, rc):
    """MQTT disconnection callback"""
    global mqtt_connected
    mqtt_connected = False
    stats["connected"] = False
    logger.info("Disconnected from MQTT broker")
    socketio.emit('mqtt_status', {'connected': False})


def on_message(client, userdata, msg):
    """MQTT message callback"""
    try:
        topic = msg.topic
        payload = msg.payload.decode('utf-8', errors='replace')
        
        # Try to parse as JSON
        try:
            payload_json = json.loads(payload)
            payload_display = json.dumps(payload_json, indent=2)
        except:
            payload_display = payload
        
        message_data = {
            "timestamp": datetime.now().isoformat(),
            "topic": topic,
            "payload": payload,
            "payload_display": payload_display,
            "qos": msg.qos,
            "retain": msg.retain
        }
        
        messages.append(message_data)
        stats["messages_received"] += 1
        stats["last_message_time"] = datetime.now().isoformat()
        
        # Track topics
        if topic not in subscribed_topics:
            subscribed_topics.add(topic)
            stats["topics_count"] = len(subscribed_topics)
        
        # Emit to WebSocket clients
        socketio.emit('mqtt_message', message_data)
        
    except Exception as e:
        logger.error(f"Error processing MQTT message: {e}")


def on_publish(client, userdata, mid):
    """MQTT publish callback"""
    stats["messages_published"] += 1


def init_mqtt():
    """Initialize MQTT client"""
    global mqtt_client
    load_mqtt_config()
    
    mqtt_client = mqtt.Client(client_id="mqtt-debug-web")
    mqtt_client.username_pw_set(MQTT_USERNAME, MQTT_PASSWORD)
    mqtt_client.on_connect = on_connect
    mqtt_client.on_disconnect = on_disconnect
    mqtt_client.on_message = on_message
    mqtt_client.on_publish = on_publish
    
    try:
        mqtt_client.connect(MQTT_BROKER, MQTT_PORT, 60)
        mqtt_client.loop_start()
        logger.info(f"MQTT client initialized, connecting to {MQTT_BROKER}:{MQTT_PORT}")
    except Exception as e:
        logger.error(f"Failed to initialize MQTT client: {e}")


# HTML Template
HTML_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <title>MQTT Debug Interface - Essensys</title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <script src="https://cdn.socket.io/4.5.4/socket.io.min.js"></script>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: #1e1e1e;
            color: #d4d4d4;
            padding: 20px;
        }
        .header {
            background: #2d2d30;
            padding: 15px;
            border-radius: 5px;
            margin-bottom: 20px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .status {
            display: inline-block;
            padding: 5px 10px;
            border-radius: 3px;
            font-weight: bold;
        }
        .status.connected { background: #4caf50; color: white; }
        .status.disconnected { background: #f44336; color: white; }
        .container {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 20px;
        }
        @media (max-width: 1200px) {
            .container { grid-template-columns: 1fr; }
        }
        .panel {
            background: #2d2d30;
            border-radius: 5px;
            padding: 15px;
        }
        .panel h2 {
            margin-bottom: 15px;
            color: #4ec9b0;
            border-bottom: 2px solid #4ec9b0;
            padding-bottom: 5px;
        }
        .stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 10px;
            margin-bottom: 15px;
        }
        .stat-item {
            background: #1e1e1e;
            padding: 10px;
            border-radius: 3px;
            text-align: center;
        }
        .stat-value {
            font-size: 24px;
            font-weight: bold;
            color: #4ec9b0;
        }
        .stat-label {
            font-size: 12px;
            color: #858585;
            margin-top: 5px;
        }
        .messages {
            max-height: 600px;
            overflow-y: auto;
            background: #1e1e1e;
            border-radius: 3px;
            padding: 10px;
        }
        .message {
            background: #252526;
            margin-bottom: 10px;
            padding: 10px;
            border-radius: 3px;
            border-left: 3px solid #4ec9b0;
            font-size: 12px;
        }
        .message-header {
            display: flex;
            justify-content: space-between;
            margin-bottom: 5px;
        }
        .message-topic {
            color: #4ec9b0;
            font-weight: bold;
        }
        .message-time {
            color: #858585;
            font-size: 11px;
        }
        .message-payload {
            background: #1e1e1e;
            padding: 8px;
            border-radius: 3px;
            margin-top: 5px;
            white-space: pre-wrap;
            font-family: 'Courier New', monospace;
            font-size: 11px;
            max-height: 200px;
            overflow-y: auto;
        }
        .publish-form {
            display: grid;
            gap: 10px;
        }
        .form-group {
            display: flex;
            flex-direction: column;
        }
        .form-group label {
            margin-bottom: 5px;
            color: #858585;
        }
        input, textarea, select {
            background: #1e1e1e;
            border: 1px solid #3e3e42;
            color: #d4d4d4;
            padding: 8px;
            border-radius: 3px;
            font-family: inherit;
        }
        input:focus, textarea:focus, select:focus {
            outline: none;
            border-color: #4ec9b0;
        }
        button {
            background: #0e639c;
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 3px;
            cursor: pointer;
            font-weight: bold;
        }
        button:hover {
            background: #1177bb;
        }
        .topics-list {
            max-height: 300px;
            overflow-y: auto;
            background: #1e1e1e;
            border-radius: 3px;
            padding: 10px;
        }
        .topic-item {
            padding: 5px;
            margin: 2px 0;
            background: #252526;
            border-radius: 3px;
            font-family: 'Courier New', monospace;
            font-size: 12px;
        }
        .controls {
            display: flex;
            gap: 10px;
            margin-bottom: 15px;
        }
        button.secondary {
            background: #3e3e42;
        }
        button.secondary:hover {
            background: #4e4e52;
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>MQTT Debug Interface - Essensys</h1>
        <div>
            <span class="status disconnected" id="status">Disconnected</span>
        </div>
    </div>
    
    <div class="container">
        <div class="panel">
            <h2>Statistics</h2>
            <div class="stats">
                <div class="stat-item">
                    <div class="stat-value" id="stat-messages">0</div>
                    <div class="stat-label">Messages Received</div>
                </div>
                <div class="stat-item">
                    <div class="stat-value" id="stat-published">0</div>
                    <div class="stat-label">Messages Published</div>
                </div>
                <div class="stat-item">
                    <div class="stat-value" id="stat-topics">0</div>
                    <div class="stat-label">Topics</div>
                </div>
            </div>
            
            <h2>Messages</h2>
            <div class="controls">
                <button onclick="clearMessages()" class="secondary">Clear</button>
                <button onclick="toggleAutoScroll()" id="autoscroll-btn">Auto-scroll: ON</button>
            </div>
            <div class="messages" id="messages"></div>
        </div>
        
        <div class="panel">
            <h2>Publish Message</h2>
            <form class="publish-form" onsubmit="publishMessage(event)">
                <div class="form-group">
                    <label>Topic</label>
                    <input type="text" id="publish-topic" placeholder="essensys/test/topic" required>
                </div>
                <div class="form-group">
                    <label>Payload</label>
                    <textarea id="publish-payload" rows="5" placeholder='{"key": "value"}'></textarea>
                </div>
                <div class="form-group">
                    <label>QoS</label>
                    <select id="publish-qos">
                        <option value="0">0 - At most once</option>
                        <option value="1" selected>1 - At least once</option>
                        <option value="2">2 - Exactly once</option>
                    </select>
                </div>
                <div class="form-group">
                    <label>
                        <input type="checkbox" id="publish-retain"> Retain message
                    </label>
                </div>
                <button type="submit">Publish</button>
            </form>
            
            <h2 style="margin-top: 20px;">Subscribed Topics</h2>
            <div class="topics-list" id="topics"></div>
        </div>
    </div>
    
    <script>
        const socket = io();
        let autoScroll = true;
        
        socket.on('connect', () => {
            console.log('WebSocket connected');
        });
        
        socket.on('mqtt_status', (data) => {
            const statusEl = document.getElementById('status');
            if (data.connected) {
                statusEl.textContent = 'Connected';
                statusEl.className = 'status connected';
            } else {
                statusEl.textContent = 'Disconnected';
                statusEl.className = 'status disconnected';
            }
        });
        
        socket.on('mqtt_message', (data) => {
            addMessage(data);
            updateStats();
        });
        
        socket.on('stats_update', (data) => {
            updateStats(data);
        });
        
        function addMessage(data) {
            const messagesDiv = document.getElementById('messages');
            const messageDiv = document.createElement('div');
            messageDiv.className = 'message';
            messageDiv.innerHTML = `
                <div class="message-header">
                    <span class="message-topic">${escapeHtml(data.topic)}</span>
                    <span class="message-time">${data.timestamp}</span>
                </div>
                <div class="message-payload">${escapeHtml(data.payload_display)}</div>
            `;
            messagesDiv.appendChild(messageDiv);
            
            if (autoScroll) {
                messagesDiv.scrollTop = messagesDiv.scrollHeight;
            }
        }
        
        function publishMessage(event) {
            event.preventDefault();
            const topic = document.getElementById('publish-topic').value;
            const payload = document.getElementById('publish-payload').value;
            const qos = parseInt(document.getElementById('publish-qos').value);
            const retain = document.getElementById('publish-retain').checked;
            
            socket.emit('publish', {
                topic: topic,
                payload: payload,
                qos: qos,
                retain: retain
            });
        }
        
        function clearMessages() {
            document.getElementById('messages').innerHTML = '';
        }
        
        function toggleAutoScroll() {
            autoScroll = !autoScroll;
            document.getElementById('autoscroll-btn').textContent = 
                `Auto-scroll: ${autoScroll ? 'ON' : 'OFF'}`;
        }
        
        function updateStats(data) {
            if (data) {
                document.getElementById('stat-messages').textContent = data.messages_received || 0;
                document.getElementById('stat-published').textContent = data.messages_published || 0;
                document.getElementById('stat-topics').textContent = data.topics_count || 0;
            }
        }
        
        function escapeHtml(text) {
            const div = document.createElement('div');
            div.textContent = text;
            return div.innerHTML;
        }
        
        // Request initial stats
        socket.emit('get_stats');
        
        // Update topics list
        socket.on('topics_update', (topics) => {
            const topicsDiv = document.getElementById('topics');
            topicsDiv.innerHTML = '';
            topics.forEach(topic => {
                const div = document.createElement('div');
                div.className = 'topic-item';
                div.textContent = topic;
                topicsDiv.appendChild(div);
            });
        });
        
        // Request topics update
        socket.emit('get_topics');
    </script>
</body>
</html>
"""


@app.route('/')
def index():
    """Main page"""
    return render_template_string(HTML_TEMPLATE)


@app.route('/api/stats')
def get_stats():
    """Get MQTT statistics"""
    return jsonify(stats)


@app.route('/api/messages')
def get_messages():
    """Get recent messages"""
    return jsonify(list(messages))


@app.route('/api/topics')
def get_topics():
    """Get subscribed topics"""
    return jsonify(list(subscribed_topics))


@socketio.on('connect')
def handle_connect():
    """WebSocket connect"""
    emit('mqtt_status', {'connected': mqtt_connected})
    emit('stats_update', stats)
    emit('topics_update', list(subscribed_topics))


@socketio.on('get_stats')
def handle_get_stats():
    """Send stats to client"""
    emit('stats_update', stats)


@socketio.on('get_topics')
def handle_get_topics():
    """Send topics to client"""
    emit('topics_update', list(subscribed_topics))


@socketio.on('publish')
def handle_publish(data):
    """Publish MQTT message"""
    if not mqtt_client or not mqtt_connected:
        emit('error', {'message': 'MQTT client not connected'})
        return
    
    try:
        topic = data.get('topic')
        payload = data.get('payload', '')
        qos = data.get('qos', 1)
        retain = data.get('retain', False)
        
        result = mqtt_client.publish(topic, payload, qos=qos, retain=retain)
        if result.rc == mqtt.MQTT_ERR_SUCCESS:
            emit('publish_success', {'topic': topic, 'payload': payload})
        else:
            emit('error', {'message': f'Failed to publish: {result.rc}'})
    except Exception as e:
        emit('error', {'message': str(e)})


def stats_updater():
    """Periodically send stats updates"""
    while True:
        time.sleep(5)
        socketio.emit('stats_update', stats)
        socketio.emit('topics_update', list(subscribed_topics))


if __name__ == '__main__':
    # Start stats updater thread
    threading.Thread(target=stats_updater, daemon=True).start()
    
    # Initialize MQTT
    init_mqtt()
    
    # Start Flask app
    logger.info(f"Starting MQTT Debug Interface on port {WEB_PORT}")
    socketio.run(app, host='0.0.0.0', port=WEB_PORT, debug=DEBUG, allow_unsafe_werkzeug=True)
