require_relative '../spec_helper'

describe Annotate do
  describe 'VERSION' do
    it 'has version' do
      expect(Annotate::VERSION).to be_instance_of(String)
    end
  end
end
