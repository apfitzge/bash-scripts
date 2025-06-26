SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

source ${SCRIPT_DIR}/bash_scripts.sh
source ${SCRIPT_DIR}/ssh_scripts.sh
source ${SCRIPT_DIR}/git_scripts.sh
source ${SCRIPT_DIR}/rust_scripts.sh
source ${SCRIPT_DIR}/solana_scripts.sh
source ${SCRIPT_DIR}/perf_scripts.sh
