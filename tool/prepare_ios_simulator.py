import json
import os
import subprocess


def read(kind):
    return json.loads(subprocess.check_output(["xcrun", "simctl", "list", kind, "--json"]))


runtimes = [
    r for r in read("runtimes")["runtimes"]
    if r.get("isAvailable") and r["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")
]
if not runtimes:
    raise SystemExit("No available iOS runtime")
runtime = max(runtimes, key=lambda r: tuple(map(int, r["version"].split("."))))
phones = [
    d for d in read("devices")["devices"].get(runtime["identifier"], [])
    if d.get("isAvailable") and d["name"].startswith("iPhone")
]
if not phones:
    raise SystemExit("No available iPhone for this iOS runtime")
selected = next((d for d in phones if d["state"] == "Booted"), phones[0])
with open(os.environ["GITHUB_ENV"], "a") as file:
    file.write(f"TF_SIMULATOR={selected['udid']}\n")
if selected["state"] != "Booted":
    subprocess.check_call(["xcrun", "simctl", "boot", selected["udid"]])
subprocess.check_call(["xcrun", "simctl", "bootstatus", selected["udid"], "-b"])
print(f"Fictional OCR simulator ready: iOS {runtime['version']}")
