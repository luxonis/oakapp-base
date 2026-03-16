import signal
import sys
import time

shutdown_requested = False


def handle_term(signum, frame):
    global shutdown_requested
    print("APP: received SIGTERM, starting graceful shutdown...")
    shutdown_requested = True


signal.signal(signal.SIGTERM, handle_term)
signal.signal(signal.SIGINT, handle_term)

print("APP: started")

try:
    while not shutdown_requested:
        print("APP: working...")
        time.sleep(5.)
        raise RuntimeError("Unhandled Exception")

    print("APP: cleaning up for 5 seconds...")
    time.sleep(5)
    print("APP: graceful shutdown complete")
    sys.exit(0)

except Exception as e:
    print(f"APP: fatal error: {e}")
    sys.exit(1)
