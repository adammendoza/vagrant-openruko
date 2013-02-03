#
# Cookbook Name:: postgresql
# Recipe:: server
#

include_recipe "postgresql"

pg_version = node["postgresql"]["version"]

# install the package
package "postgresql-#{pg_version}"

# Make sure /etc/postgresql/9.1/main exists.
# For some reason Travis CI doesn't create it.
bash "postgres-dir" do
  user  "root"
  code <<-EOF
  mkdir -p #{node['postgresql']['dir']}
  EOF
end

# ensure data directory exists
directory node["postgresql"]["data_directory"] do
  owner  "postgres"
  group  "postgres"
  mode   "0700"
  not_if "test -f #{node["postgresql"]["data_directory"]}/PG_VERSION"
end

# initialize the data directory if necessary
bash "postgresql initdb" do
  user "postgres"
  code <<-EOC
  /usr/lib/postgresql/#{pg_version}/bin/initdb \
    #{node["postgresql"]["initdb_options"]} \
    -U postgres \
    -D #{node["postgresql"]["data_directory"]}
  EOC
  creates "#{node["postgresql"]["data_directory"]}/PG_VERSION"
end

# environment
template "/etc/postgresql/#{pg_version}/main/environment" do
  source "environment.erb"
  owner  "postgres"
  group  "postgres"
  mode   "0644"
  notifies :restart, "service[postgresql]"
end

# pg_ctl
template "/etc/postgresql/#{pg_version}/main/pg_ctl.conf" do
  source "pg_ctl.conf.erb"
  owner  "postgres"
  group  "postgres"
  mode   "0644"
  notifies :restart, "service[postgresql]"
end

# pg_hba
template node["postgresql"]["hba_file"] do
  source "pg_hba.conf.erb"
  owner  "postgres"
  group  "postgres"
  mode   "0640"
  notifies :restart, "service[postgresql]"
end

# pg_ident
template node["postgresql"]["ident_file"] do
  source "pg_ident.conf.erb"
  owner  "postgres"
  group  "postgres"
  mode   "0640"
  notifies :restart, "service[postgresql]"
end

# postgresql
pg_template_source = node["postgresql"]["conf"].any? ? "custom" : "standard"
template "/etc/postgresql/#{pg_version}/main/postgresql.conf" do
  source "postgresql.conf.#{pg_template_source}.erb"
  owner  "postgres"
  group  "postgres"
  mode   "0644"
  variables(:configuration => node["postgresql"]["conf"])
  notifies :restart, "service[postgresql]"
end

# start
template "/etc/postgresql/#{pg_version}/main/start.conf" do
  source "start.conf.erb"
  owner  "postgres"
  group  "postgres"
  mode   "0644"
  notifies :restart, "service[postgresql]", :immediately
end

# setup users
node["postgresql"]["users"].each do |user|
  pg_user user["username"] do
    privileges :superuser => user["superuser"], :createdb => user["createdb"], :login => user["login"]
    password user["password"]
  end
end

# setup databases
node["postgresql"]["databases"].each do |database|
  pg_database database["name"] do
    owner database["owner"]
    encoding database["encoding"]
    template database["template"]
    locale database["locale"]
  end

  pg_database_extensions database["name"] do
    extensions database["extensions"]
    languages database["languages"]
    postgis database["postgis"]
  end
end

# define the service
service "postgresql" do
  supports :restart => true
  action [:enable, :start]
end
