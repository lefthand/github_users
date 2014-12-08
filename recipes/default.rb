require 'json'
require 'open-uri'

usernames = []
headers = {}

package 'git' if node['github_users']['fetch_dotfiles']

if node['github_users']['auth_token']
    headers = {"Authorization" => "token #{node['github_users']['auth_token']}"}
end

if node['github_users']['organization']
    begin
        usernames = JSON.parse(
            open("https://api.github.com/orgs/#{node['github_users']['organization']}/public_members").read
        ).map{|u| u['login']}
    rescue OpenURI::HTTPError => e
        log "Got a HTTP error while connecting to Github - #{e.message}"
        return
    end
elsif node['github_users']['team']
    begin
        usernames = JSON.parse(
            open("https://api.github.com/teams/#{node['github_users']['team']}/members", headers).read
        ).map{|u| u['login']}
    rescue OpenURI::HTTPError => e
        log "Got a HTTP error while connecting to Github - #{e.message}"
        return
    end
elsif node['github_users']['users']
    usernames = node['github_users']['users']
end

group node['github_users']['group_name'] do
    gid node['github_users']['group_id']
    action :create
end

group_name = node['github_users']['group_name']
existing_group_users = node['etc']['group'].fetch(group_name, {}).fetch('members', [])
users_to_delete = existing_group_users - usernames

users_to_delete.each do |user_to_delete|
    log "Removing stale user #{user_to_delete} from group:"
    user user_to_delete do
        action :remove
    end
end

usernames.each do |username|
    public_keys = []
    begin 
        public_keys = JSON.parse(
            open("https://api.github.com/users/#{username}/keys", headers).read
        ).map{|k| k['key']}
    rescue OpenURI::HTTPError => e
        log "Got a HTTP error while connecting to Github - #{e.message}"
        return
    end

    user username do
        comment "Github User #{username}"
        gid node['github_users']['group_name']
        home "/home/#{username}"
        shell node['github_users']['custom_shells'].key?(username) ? node['github_users']['custom_shells'][username] : "/bin/bash"
        system true
        supports :manage_home => true

        action :create
    end

    if node['github_users']['fetch_dotfiles']
        begin
            open("https://api.github.com/repos/#{username}/dotfiles")
            git "/home/#{username}/Dotfiles" do
                repository "https://github.com/#{username}/dotfiles.git"
                action :sync
                user username
                group group_name
                notifies :run, "bash[copy_dotfiles]", :immediately
            end
            bash "copy_dotfiles" do
                cwd "/home/#{username}"
                user username
                group group_name
                code "ln -st /home/#{username} /home/#{username}/Dotfiles/{.??*,*}; rm /home/#{username}/.git"
                action :nothing
            end
        rescue OpenURI::HTTPError
            log "Repository dotfiles for user #{username} not found"
        end
    end

    directory "/home/#{username}/.ssh" do
        owner username
        group node['github_users']['group_name']
        mode "0700"
        action :create
    end

    template "/home/#{username}/.ssh/authorized_keys" do
        source "authorized_keys.erb"
        owner username
        group node['github_users']['group_name']
        mode "0600"
        variables(
            :public_keys => public_keys
        )
    end

    if node['github_users']['allow_sudo']
        node.default['authorization']['sudo']['include_sudoers_d'] = true

        sudo node['github_users']['group_name'] do
            group node['github_users']['group_name']
            nopasswd true
        end 
    end
end

group node['github_users']['group_name'] do
    members usernames
    action :modify
end
