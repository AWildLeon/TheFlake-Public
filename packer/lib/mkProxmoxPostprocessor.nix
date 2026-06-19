{
  pkgs,
  vm_id,
  ...
}:
let
  script = pkgs.writeShellScript "proxmox-postprocessor.sh" ''
    set -euo pipefail
    exec 2>&1 > ./proxmox-postprocessor.log

    echo "Running post-processor script for VM ID ${vm_id}"

    cleanup() {
      # Check if the temporary directory exists before attempting to remove it.
      if [[ -d "$tmpdir" ]]; then
        echo "Cleaning up temporary directory: $tmpdir"
        rm -rf "$tmpdir"
      fi
    }
    trap cleanup EXIT

    tmpdir=$(mktemp -d)
    echo "Created temporary directory: $tmpdir"

    cd $tmpdir
    # Create Ansible inventory file with localhost only.
    cat <<EOF > inventory.json
    {
      "local": {
        "hosts": {
          "localhost": {
            "ansible_connection": "local",
            "proxmox_url": "$proxmox_url",
            "proxmox_username": "$proxmox_username",
            "proxmox_token": "$proxmox_token",
            "proxmox_node": "$proxmox_node",
            "proxmox_vm_id": "$proxmox_vm_id"
          }
        }
      }
    }
    EOF
    # Run the Ansible playbook to perform post-processing tasks on the Proxmox VM.
    ansible-playbook -i inventory.json ${ansiblePlaybook}
  '';
  ansiblePlaybook = ./postprocessor-proxmox-playbook.yml;

  python = pkgs.python3.withPackages (
    python-pkgs: with python-pkgs; [
      # select Python packages here
      proxmoxer
      requests
    ]
  );
  postProcessDeps = with pkgs; [
    openssh
    python
    ansible
    coreutils
    bash
  ];
in
{
  type = "shell-local";
  environment_vars = [
    "PATH=${pkgs.lib.makeBinPath postProcessDeps}"
    "ANSIBLE_PYTHON_INTERPRETER=${python}/bin/python"
    "proxmox_url={{user `proxmox_url`}}"
    "proxmox_username={{user `proxmox_api_token_id`}}"
    "proxmox_token={{user `proxmox_api_token_secret`}}"
    "proxmox_node={{user `proxmox_node`}}"
    "proxmox_vm_id=${vm_id}"
  ];
  inherit script;
}
