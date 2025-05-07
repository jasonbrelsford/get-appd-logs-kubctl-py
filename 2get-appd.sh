#!/bin/bash
#Copyright Jason Brelsford
#“This software is licensed under CC BY-NC 4.0. For commercial use, please contact @jasonbrelsford.”
#
set -e

# 🔍 Step 1: Ensure KUBECONFIG is set
check_kubeconfig() {
  if [[ -n "$KUBECONFIG" ]]; then
    echo "✅ KUBECONFIG is already set to: $KUBECONFIG"
  elif [[ -f "$HOME/kubeconfig.yaml" ]]; then
    export KUBECONFIG="$HOME/kubeconfig.yaml"
    echo "✅ Found kubeconfig at ~/kubeconfig.yaml. Using it."
  else
    echo "⚠️ No KUBECONFIG found. Please paste your kubeconfig content below."
    echo "Paste the entire kubeconfig (end with Ctrl+D):"
    TMP_KUBECONFIG=$(mktemp)
    cat > "$TMP_KUBECONFIG"
    mv "$TMP_KUBECONFIG" "$HOME/kubeconfig.yaml"
    chmod 600 "$HOME/kubeconfig.yaml"
    export KUBECONFIG="$HOME/kubeconfig.yaml"
    echo "✅ Kubeconfig saved to ~/kubeconfig.yaml and exported."
  fi
}

# 🎯 Step 2: Choose context and namespace
select_context_and_namespace() {
  echo "📡 Available Kubernetes contexts:"
  kubectl config get-contexts -o name
  echo ""
  read -p "👉 Enter the context to use: " CONTEXT
  kubectl config use-context "$CONTEXT"

  echo ""
  echo "📂 Available namespaces in $CONTEXT:"
  kubectl get ns --no-headers -o custom-columns=":metadata.name"
  echo ""
  read -p "👉 Enter the namespace to use: " NAMESPACE
}

# 📦 Step 3: Choose pods
select_pods() {
  echo ""
  echo "📦 Available pods in namespace '$NAMESPACE':"
  kubectl get pods -n "$NAMESPACE" --no-headers -o custom-columns=":metadata.name"
  echo ""
  read -p "👉 Enter pod names separated by space (or type 'all' for all pods): " -a PODS_INPUT

  if [[ "${PODS_INPUT[0]}" == "all" ]]; then
    PODS=()
    while IFS= read -r pod_name; do
      PODS+=("$pod_name")
    done < <(kubectl get pods -n "$NAMESPACE" --no-headers -o custom-columns=":metadata.name")
  else
    PODS=("${PODS_INPUT[@]}")
  fi
}


# 🏁 Step 4: Download AppDynamics Logs
download_logs() {
  echo ""
  echo "📁 Checking available AppDynamics directories in the first pod..."
  TEST_POD="${PODS[0]}"
  DIR_LIST=$(kubectl exec -n "$NAMESPACE" "$TEST_POD" -- ls /opt/appdynamics-java 2>/dev/null || true)

  if [[ -z "$DIR_LIST" ]]; then
    echo "❌ Cannot find /opt/appdynamics-java in $TEST_POD"
    return
  fi

  echo "📂 Found directories:"
  echo "$DIR_LIST"
  echo ""
  read -p "👉 Enter one of the above directories to collect logs from, or type 'all' to get all: " SELECTED_DIR

  for POD in "${PODS[@]}"; do
    echo "🔍 Getting logs from $POD..."

    if [[ "$SELECTED_DIR" == "all" ]]; then
      DIRS=$(kubectl exec -n "$NAMESPACE" "$POD" -- ls /opt/appdynamics-java 2>/dev/null || true)
    else
      DIRS="$SELECTED_DIR"
    fi

    for DIR in $DIRS; do
      LOG_PATH="/opt/appdynamics-java/$DIR/logs"
      LOCAL_DIR="./appd-logs-$POD-$DIR"
      echo "📁 Copying logs from $LOG_PATH in $POD to $LOCAL_DIR..."

      mkdir -p "$LOCAL_DIR"
      if kubectl cp "$NAMESPACE/$POD:$LOG_PATH" "$LOCAL_DIR"; then
        echo "🗜️  Zipping $LOCAL_DIR to $LOCAL_DIR.zip"
        zip -r "$LOCAL_DIR.zip" "$LOCAL_DIR"
        rm -rf "$LOCAL_DIR"
        echo "✅ Logs collected for $POD / $DIR"
      else
        echo "⚠️  Failed to copy from $POD:$LOG_PATH — skipping"
        rm -rf "$LOCAL_DIR"
      fi
      echo "----------------------------------"
    done
  done
}

# 🚀 Run the script
check_kubeconfig
select_context_and_namespace
select_pods
download_logs

