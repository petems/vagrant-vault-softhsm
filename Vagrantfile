# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  config.vm.box = "bento/debian-9"

  # config.vm.provision "shell", path: "setup_softhsm.sh"
  config.vm.provision "shell", path: "setup_vault.sh"

  config.vm.network :forwarded_port, guest: 8200, host: 8200, id: "vault"

end
