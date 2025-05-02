import os
import tempfile
import subprocess
import shutil
from datetime import datetime

# --- Ensure required modules are installed ---
try:
    from flask import Flask, request, render_template_string, send_file
except ImportError:
    subprocess.check_call(["python3", "-m", "pip", "install", "flask"])
    from flask import Flask, request, render_template_string, send_file

app = Flask(__name__)

HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang=\"en\">
<head>
    <meta charset=\"UTF-8\">
    <title>Kubeconfig & AppD Logs</title>
</head>
<body>
    <h2>Paste Your Kubeconfig</h2>
    <form method=\"POST\" action=\"/download\">
        <textarea name=\"kubeconfig\" rows=\"20\" cols=\"80\" required></textarea><br><br>
        Namespace: <input type=\"text\" name=\"namespace\" required><br><br>
        Pods (comma-separated): <input type=\"text\" name=\"pods\" required><br><br>
        <input type=\"submit\" value=\"Download AppD Logs\">
    </form>
</body>
</html>
"""

@app.route("/", methods=["GET"])
def index():
    return render_template_string(HTML_TEMPLATE)

@app.route("/download", methods=["POST"])
def download_logs():
    kubeconfig_content = request.form['kubeconfig']
    namespace = request.form['namespace']
    pods = [pod.strip() for pod in request.form['pods'].split(',')]

    # Create temp dir and kubeconfig file
    work_dir = tempfile.mkdtemp()
    kubeconfig_path = os.path.join(work_dir, 'kubeconfig.yaml')
    with open(kubeconfig_path, 'w') as f:
        f.write(kubeconfig_content)

    env = os.environ.copy()
    env['KUBECONFIG'] = kubeconfig_path

    zip_files = []
    for pod in pods:
        log_path = "/opt/appdynamics-java/ver24.12.0.36528/logs"
        local_dir = os.path.join(work_dir, f"appd-logs-{pod}")
        os.makedirs(local_dir, exist_ok=True)

        subprocess.run([
            "kubectl", "cp",
            f"{namespace}/{pod}:{log_path}",
            local_dir
        ], env=env, check=False)

        shutil.make_archive(local_dir, 'zip', local_dir)
        zip_files.append(f"{local_dir}.zip")

    # Combine into a single zip file for download
    final_zip = os.path.join(work_dir, f"appd_logs_{datetime.now().strftime('%Y%m%d_%H%M%S')}.zip")
    shutil.make_archive(final_zip.replace('.zip', ''), 'zip', work_dir)

    return send_file(final_zip, as_attachment=True)

if __name__ == "__main__":
    app.run(debug=True, port=5000)
