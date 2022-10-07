# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Scelint do
  it 'has a version number' do
    expect(Scelint::VERSION).not_to be_nil
  end

  it 'initializes' do
    lint = Scelint::Lint.new
    expect(lint).not_to be_nil
    expect(lint).to be_instance_of(Scelint::Lint)
  end
end
