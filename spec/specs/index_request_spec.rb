require 'light_spec_helper'
require 'net/ssh/errors'
require 'timeout'
require 'flying_sphinx/index_request'

describe FlyingSphinx::IndexRequest do
  let(:api)           { fire_double('FlyingSphinx::API') }
  let(:configuration) { stub(:configuration, :api => api) }
  let(:tunnel_class)  { fire_class_double('FlyingSphinx::Tunnel').
    as_replaced_constant }

  let(:index_response)    {
    stub(:response, :body => stub(:body, :id => 42, :status => 'OK'))
  }
  let(:blocked_response)  {
    stub(:response, :body => stub(:body, :id => nil, :status => 'BLOCKED'))
  }

  before :each do
    stub_const 'FlyingSphinx::Configuration', double(:new => configuration)

    stub_const 'FlyingSphinx::IndexRequest::INDEX_COMPLETE_CHECKING_INTERVAL',
      0
  end

  describe '.cancel_jobs' do
    let(:job_class) { fire_class_double('Delayed::Job').as_replaced_constant }

    before :each do
      job_class.stub :delete_all => true
    end

    it "should not delete any rows if the delayed_jobs table does not exist" do
      job_class.stub :table_exists? => false

      job_class.should_not_receive(:delete_all)

      FlyingSphinx::IndexRequest.cancel_jobs
    end

    it "should delete rows if the delayed_jobs table does exist" do
      job_class.stub :table_exists? => true

      job_class.should_receive(:delete_all)

      FlyingSphinx::IndexRequest.cancel_jobs
    end

    it "should delete only Thinking Sphinx jobs" do
      job_class.stub :table_exists? => true

      job_class.should_receive(:delete_all) do |sql|
        sql.should match(/handler LIKE '--- !ruby\/object:FlyingSphinx::\%'/)
      end

      FlyingSphinx::IndexRequest.cancel_jobs
    end
  end

  describe '#update_and_index' do
    let(:index_request) { FlyingSphinx::IndexRequest.new }
    let(:conf_params)   { { :configuration => 'foo {}',
      :sphinx_version => '2.1.0-dev' } }
    let(:index_params)  { { :indices => '' } }
    let(:sphinx)        { fire_double('FlyingSphinx::SphinxConfiguration',
      :upload_to => true)}
    let(:setting_files) { fire_double('FlyingSphinx::SettingFiles',
      :upload_to => true) }

    before :each do
      stub_const 'FlyingSphinx::SettingFiles', double(:new => setting_files)
      stub_const 'FlyingSphinx::SphinxConfiguration', double(:new => sphinx)

      api.stub :post => index_response

      tunnel_class.stub :required? => true
      tunnel_class.stub(:connect).and_yield
    end

    it "uploads the configuration file" do
      sphinx.should_receive(:upload_to).with(api, true)

      begin
        Timeout::timeout(0.2) {
          index_request.update_and_index
        }
      rescue Timeout::Error
      end
    end

    it "uploads setting files" do
      setting_files.should_receive(:upload_to).with(api)

      begin
        Timeout::timeout(0.2) {
          index_request.update_and_index
        }
      rescue Timeout::Error
      end
    end

    it "makes a new request" do
      api.should_receive(:post).
        with('indices', index_params).and_return(index_response)

      begin
        Timeout::timeout(0.2) {
          index_request.update_and_index
        }
      rescue Timeout::Error
      end
    end

    context 'delta request without delta support' do
      it "should explain why the request failed" do
        api.should_receive(:post).
          with('indices', index_params).and_return(blocked_response)
        index_request.should_receive(:puts).
          with('Your account does not support delta indexing. Upgrading plans is probably the best way around this.')

        index_request.update_and_index
      end
    end

    context 'request for a MySQL database' do
      before :each do
        tunnel_class.stub :required? => false
      end

      it "should not establish an SSH connection" do
        FlyingSphinx::Tunnel.should_not_receive(:connect)

        api.should_receive(:post).
          with('indices', index_params).and_return(index_response)
        api.should_receive(:get).with('indices/42').
          and_return(stub(:response, :body => stub(:body, :status => 'FINISHED')))

        index_request.update_and_index
      end
    end
  end

  describe '#perform' do
    let(:index_request) { FlyingSphinx::IndexRequest.new ['foo_delta'] }
    let(:index_params)  { { :indices => 'foo_delta' } }

    before :each do
      tunnel_class.stub :required? => true
      tunnel_class.stub(:connect).and_yield
    end

    it "makes a new request" do
      api.should_receive(:post).
        with('indices', index_params).and_return(index_response)

      begin
        Timeout::timeout(0.2) {
          index_request.perform
        }
      rescue Timeout::Error
      end
    end
  end

  describe '#status_message' do
    let(:index_request)     { FlyingSphinx::IndexRequest.new }
    let(:finished_response) {
      stub(:response, :body => stub(:body, :status => 'FINISHED'))
    }
    let(:failure_response)  {
      stub(:response, :body => stub(:body, :status => 'FAILED'))
    }
    let(:pending_response)  {
      stub(:response, :body => stub(:body, :status => 'PENDING'))
    }
    let(:unknown_response)  {
      stub(:response, :body => stub(:body, :status => 'UNKNOWN'))
    }

    before :each do
      api.stub(:post => index_response)

      index_request.instance_variable_set :@index_id, 42
    end

    it "returns with a positive message on success" do
      api.stub(:get => finished_response)

      index_request.status_message.should == 'Index Request has completed.'
    end

    it "returns with a failure message on failure" do
      api.stub(:get => failure_response)

      index_request.status_message.should == 'Index Request failed.'
    end

    it "warns the user if the request is still pending" do
      api.stub(:get => pending_response)

      index_request.status_message.should == 'Index Request is still pending - something has gone wrong.'
    end

    it "treats all other statuses as unknown" do
      api.stub(:get => unknown_response)

      index_request.status_message.should == "Unknown index response: 'UNKNOWN'."
    end

    it "raises a warning if the index id isn't set" do
      index_request.instance_variable_set :@index_id, nil

      lambda {
        index_request.status_message
      }.should raise_error
    end
  end

  describe "#display_name" do
    let(:index_request) {
      FlyingSphinx::IndexRequest.new ['foo_core', 'bar_core']
    }

    it "should display class name with all indexes" do
      index_request.display_name.should == "FlyingSphinx::IndexRequest for foo_core, bar_core"
    end
  end
end
