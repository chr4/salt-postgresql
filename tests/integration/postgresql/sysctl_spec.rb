control 'kernel parameters' do
  title 'should be configured accordingly'

  describe kernel_parameter('vm.overcommit_memory') do
    its('value') { should eq 2 }
  end
end
