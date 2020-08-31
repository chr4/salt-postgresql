version = 11

control 'postgresql' do
  title 'should be installed & configured'

  describe file('/etc/apt/sources.list.d/apt.postgresql.org.list') do
    its('content') { should match /^deb http:\/\/apt.postgresql.org\/pub\/repos\/apt / }
  end

  describe package("postgresql-#{version}") do
    it { should be_installed }
  end

  describe postgres_conf("/etc/postgresql/#{version}/main/postgresql.conf") do
    its('listen_addresses') { should eq '*' }
    its('max_connections') { should eq '100' }
    its('ssl') { should eq 'False' }
  end

  describe postgres_hba_conf("/etc/postgresql/#{version}/main/pg_hba.conf").where { user == 'user_with_password' } do
    its('type') { should cmp 'host' }
    its('database') { should cmp 'production' }
    its('address') { should cmp '10.1.2.0/24' }
    its('auth_method') { should eq ['trust'] }
  end

  %w(example_role example_user_with_role).each do |pg_user|
    describe postgres_hba_conf("/etc/postgresql/#{version}/main/pg_hba.conf").where { user == pg_user } do
      its('type') { should cmp 'host' }
      its('database') { should cmp 'staging' }
      its('address') { should cmp '10.1.2.0/24' }
      its('auth_method') { should eq ['trust'] }
    end
  end

  describe postgres_hba_conf("/etc/postgresql/#{version}/main/pg_hba.conf").where { user == 'read_only_user' } do
    its('type') { should cmp 'local' }
    its('database') { should cmp 'production' }
    its('auth_method') { should eq ['trust'] }
  end

  describe postgres_hba_conf("/etc/postgresql/#{version}/main/pg_hba.conf").where { user == 'owner' } do
    its('type') { should cmp 'host' }
    its('database') { should cmp 'db_with_extension' }
    its('address') { should cmp 'all' }
    its('auth_method') { should eq ['trust'] }
  end

  describe postgres_hba_conf("/etc/postgresql/#{version}/main/pg_hba.conf").where { user == 'replicant' } do
    its('type') { should cmp 'host' }
    its('database') { should cmp 'replication' }
    its('address') { should cmp '10.1.2.0/24' }
    its('auth_method') { should eq ['md5'] }
  end

  describe postgres_hba_conf("/etc/postgresql/#{version}/main/pg_hba.conf").where { user == 'allowall' } do
    its('type') { should cmp 'local' }
    its('database') { should cmp 'all' }
    its('auth_method') { should eq ['trust'] }
  end

  %w(beta test).each do |pg_database|
    describe postgres_hba_conf("/etc/postgresql/#{version}/main/pg_hba.conf").where { database == pg_database } do
      its('type') { should cmp 'host' }
      its('user') { should cmp 'deploy' }
      its('address') { should cmp '10.1.2.0/24' }
      its('auth_method') { should eq ['trust'] }
    end
  end

  describe postgres_hba_conf("/etc/postgresql/#{version}/main/pg_hba.conf").where { user == 'postgres' } do
    its('database') { should_not cmp 'template1' }
  end

  describe service('postgresql') do
    it { should be_enabled }
    it { should be_running }
  end

  describe port(5432) do
    it { should be_listening }
  end
end

control 'certificates' do
  title 'should be deployed'

  describe file("/var/lib/postgresql/#{version}/main/root.crt") do
    its('content') { should match /xx:xx:xx:xx:xx:xx:xx:xx/ }
  end

  describe file("/var/lib/postgresql/#{version}/main/server.crt") do
    its('content') { should match /-----BEGIN CERTIFICATE-----/ }
  end

  describe file("/var/lib/postgresql/#{version}/main/server.key") do
    its('content') { should match /-----BEGIN RSA PRIVATE KEY-----/ }
  end

end

control 'psql' do
  title 'should work'

  # Check whether connection works and create a testing table
  sql = postgres_session('postgres', '', '/run/postgresql')
  describe sql.query("CREATE TABLE tests(id SERIAL PRIMARY KEY, name VARCHAR(255));", ['production']) do
    its('output') { should eq('CREATE TABLE') }
  end
  describe sql.query("INSERT INTO tests (name) VALUES ('success');", ['production']) do
    its('output') { should eq('INSERT 0 1') }
  end

  # Assert that owner of production database is set correctly
  describe sql.query("SELECT pg_user.usename FROM pg_database JOIN pg_user ON pg_database.datdba=pg_user.usesysid WHERE datname='production';") do
    its('output') { should eq('user_with_password') }
  end

  # Assert that groups are correctly represented
  describe sql.query("SELECT rolcanlogin FROM pg_roles WHERE rolname='example_role'") do
    its('output') { should eq('f') }
  end
  describe sql.query("SELECT pg_authid.rolname FROM pg_authid WHERE pg_has_role('example_user_with_role', pg_authid.oid, 'member');") do
    its('output') { should match /example_role/ }
  end

  # Assert extensions
  describe sql.query("SELECT extname FROM pg_extension;", ['db_with_extension']) do
    its('output') { should match /pgcrypto/ }
  end

  # Assert that read only user only has read access
  sql = postgres_session('read_only_user', '', '/run/postgresql')
  describe sql.query("INSERT INTO tests (name) VALUES ('shouldfail');", ['production']) do
    its('output') { should match /permission denied for table tests/ }
  end
  describe sql.query('SELECT * FROM tests;', ['production']) do
    its('output') { should match /success/ }
    its('output') { should_not match /shouldfail/ }
  end
end
