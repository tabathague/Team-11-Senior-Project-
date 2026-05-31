import asyncio
import asyncio
import json
import websockets
import ssl

clients = set()
current_patient_id = None
current_patient_name = None

async def register(websocket):
    clients.add(websocket)
    print(f"[WS] Client connected. Total: {len(clients)}")

async def unregister(websocket):
    clients.discard(websocket)
    print(f"[WS] Client disconnected. Total: {len(clients)}")

async def handler(websocket):
    global current_patient_id, current_patient_name
    await register(websocket)
    try:
        async for message in websocket:
            try:
                data = json.loads(message)
                if "patientID" in data and "rate" not in data:
                    current_patient_id = data["patientID"]
                    current_patient_name = data.get("patientName", "Unknown")
                    print(f"[WS] Now recording for patient: {current_patient_id}")

                    forward = json.dumps({"patientID": current_patient_id})
                    others = [c for c in clients if c != websocket]
                    if others:
                        await asyncio.gather(*[c.send(forward) for c in others])
                        print(f"[WS] Forwarded patient ID to {len(others)} other client(s)")
                else:
                    # Forward sensor data from pipeline to app
                    others = [c for c in clients if c != websocket]
                    print(f"[WS] Forwarding sensor data to {len(others)} client(s): {data}")
                    await asyncio.gather(*[c.send(json.dumps(data)) for c in others])
            except json.JSONDecodeError:
                pass
    except Exception as e:
        print(f"[WS] Handler error (client likely disconnected): {e}")
    finally:
        await unregister(websocket)

async def broadcast(data):
    if clients:
        data["patientID"] = current_patient_id
        msg = json.dumps(data)
        await asyncio.gather(*[c.send(msg) for c in clients])

async def main():
    ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ssl_context.load_cert_chain("cert.pem", "key.pem")

    async with websockets.serve(
        handler,
        "0.0.0.0",
        8765,
        ssl=ssl_context,
        ping_interval=30,
        ping_timeout=60
    ):
        print("[WS] Secure server running on port 8765")
        await asyncio.Future()

asyncio.run(main())
