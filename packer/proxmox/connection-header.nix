{
  proxmox_url = "{{user `proxmox_url`}}";
  username = "{{user `proxmox_api_token_id`}}";
  token = "{{user `proxmox_api_token_secret`}}";
  node = "{{user `proxmox_node`}}";
  ssh_private_key_file = "~/.ssh/id_ed25519";
}
