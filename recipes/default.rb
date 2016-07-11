require 'json'
require 'open-uri'
require 'fileutils'

usernames = []
headers = {}

package 'git' if node['github_users']['fetch_dotfiles']

if node['github_users']['auth_token']
    headers["Authorization"] = "token #{node['github_users']['auth_token']}"
end

if node['github_users']['organization']
    begin
        usernames = JSON.parse(
            open("https://api.github.com/orgs/#{node['github_users']['organization']}/public_members?per_page=100").read
        ).map{|u| u['login']}
    rescue OpenURI::HTTPError => e
        log "Got a HTTP error while connecting to Github - #{e.message}"
        return
    end
elsif node['github_users']['team']
    begin
        usernames = JSON.parse(
            open("https://api.github.com/teams/#{node['github_users']['team']}/members?per_page=100", headers).read
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

if node['github_users']['user']
  user node['github_users']['user'] do
      gid node['github_users']['group_name']
      home "/home/#{node['github_users']['user']}"
      password node['github_users']['user_password']
      supports :manage_home => true
      action :create
  end
  directory "/home/#{node['github_users']['user']}/.ssh" do
      owner node['github_users']['user']
      group node['github_users']['group_name']
      mode "0700"
      action :create
  end

  public_keys = []
  usernames.each do |username|
      begin
          limited_headers = node['github_users']["#{username}_key_etag"] == nil ? headers : headers.merge("If-None-Match" => node['github_users']["#{username}_key_etag"])
          request = open("https://api.github.com/users/#{username}/keys", limited_headers)
          node.set['github_users']["#{username}_key_etag"] = request.meta["etag"]
          public_keys << JSON.parse(request.read).map{|k| k['key']}
      rescue OpenURI::HTTPError => e
          log "Got a HTTP error while connecting to Github - #{e.message}"
      end
  end
  template "/home/#{node['github_users']['user']}/.ssh/authorized_keys" do
      source "authorized_keys.erb"
      owner node['github_users']['user']
      group node['github_users']['group_name']
      mode "0600"
      variables(
          :public_keys => public_keys
      )
  end
else
  usernames.each do |username|
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
              limited_headers = node['github_users']["#{username}_git_etag"] == nil ? headers : headers.merge("If-None-Match" => node['github_users']["#{username}_git_etag"])
              request = open("https://api.github.com/users/#{username}/repos", limited_headers)
              node.set['github_users']["#{username}_git_etag"] = request.meta["etag"]
              repos = JSON.parse(request.read).map{|k| k['name']}
              node.set['github_users']["#{username}_git_repos"] = repos
          rescue OpenURI::HTTPError => e
              log "Repository dotfiles for user #{username} up-to-date - #{e.message}"
          end
          if node['github_users'].key?("#{username}_git_repos") and node['github_users']["#{username}_git_repos"].include?("dotfiles")
              ruby_block "fix_permissions_#{username}" do
                  block do
                      FileUtils.chown_R(username, group_name, "/home/#{username}/.dotfiles")
                  end
                  action :nothing
              end
              bash "remove_stale_links_#{username}" do
                  cwd "/home/#{username}"
                  user username
                  group group_name
                  code "find -L -maxdepth 1 -type l -delete"
                  action :nothing
              end
              ruby_block "symlink_dotfiles_#{username}" do
                  block do
                      Dir.entries("/home/#{username}/.dotfiles").select { |v| v !~ /^(\.|\.\.|\.git(|ignore|modules)|README.*|LICENSE)$/ }.each do |file_to_link|
                          FileUtils.ln_sf("/home/#{username}/.dotfiles/#{file_to_link}", "/home/#{username}/#{file_to_link}")
                          FileUtils.chown(username, group_name, "/home/#{username}/#{file_to_link}")
                      end
                  end
                  action :nothing
              end
              git "/home/#{username}/.dotfiles" do
                  repository "https://github.com/#{username}/dotfiles.git"
                  action :export
                  user username
                  group group_name
                  enable_submodules true
                  notifies :run, "ruby_block[fix_permissions_#{username}]", :immediately
                  notifies :run, "ruby_block[symlink_dotfiles_#{username}]", :immediately
                  notifies :run, "bash[remove_stale_links_#{username}]", :immediately
              end
          else
              log "Repository dotfiles for user #{username} not found"
          end
      end

      directory "/home/#{username}/.ssh" do
          owner username
          group node['github_users']['group_name']
          mode "0700"
          action :create
      end

      begin
          limited_headers = node['github_users']["#{username}_key_etag"] == nil ? headers : headers.merge("If-None-Match" => node['github_users']["#{username}_key_etag"])
          request = open("https://api.github.com/users/#{username}/keys", limited_headers)
          node.set['github_users']["#{username}_key_etag"] = request.meta["etag"]
          public_keys = JSON.parse(request.read).map{|k| k['key']}
          template "/home/#{username}/.ssh/authorized_keys" do
              source "authorized_keys.erb"
              owner username
              group node['github_users']['group_name']
              mode "0600"
              variables(
                  :public_keys => public_keys
              )
          end
      rescue OpenURI::HTTPError => e
          log "Got a HTTP error while connecting to Github - #{e.message}"
      end

  end
  group node['github_users']['group_name'] do
      members usernames
      action :modify
  end
end

if node['github_users']['allow_sudo']
    node.default['authorization']['sudo']['include_sudoers_d'] = true

    sudo node['github_users']['group_name'] do
        group node['github_users']['group_name']
        nopasswd true
    end
end
