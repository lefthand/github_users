# -*- mode: ruby -*-
# vi: set ft=ruby :
#
VAGRANTFILE_API_VERSION = '2'

Vagrant.require_version '>= 1.5.0'

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
  config.vm.hostname = "github-users-berkshelf"
  config.vm.network "public_network", :bridge => 'en0: Wi-Fi (AirPort)'
  config.vm.box = 'chef/ubuntu-14.04'
  config.vm.network :private_network, ip: "33.33.33.11"
  config.vm.network :public_network
  # config.vm.network :forwarded_port, guest: 80, host: 8086
  # config.vm.synced_folder "../data", "/vagrant_data"
  # config.berkshelf.berksfile_path = "./Berksfile"
  config.berkshelf.enabled = true
  config.vm.provision "shell", inline: <<SCRIPT
   # sudo apt-get update
   # sudo true && curl -L https://www.opscode.com/chef/install.sh | sudo bash
SCRIPT
  # config.berkshelf.only = []
  # config.berkshelf.except = []

  config.vm.provision :chef_solo do |chef|
    chef.channel = "stable"
    chef.version = "12.10.24"
    chef.json = {
      :instance_role => 'vagrant',
      :github_users => {
        :users => ["user1","user2","user3"],
        :group_name => 'my-group',
        :user => 'my-user'
      }
    }
    chef.run_list = [
        "recipe[github_users]"
    ]
  end
end
#require 'berkshelf/vagrant'
