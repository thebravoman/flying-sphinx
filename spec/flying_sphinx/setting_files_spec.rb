require 'spec_helper'

describe FlyingSphinx::SettingFiles do
  let(:files)   { FlyingSphinx::SettingFiles.new indices }
  let(:indices) { [] }

  def index_double(methods)
    double 'Riddle::Configuration::Index', methods
  end

  def source_double(methods)
    double 'Riddle::Configuration::SQLSource', methods
  end

  describe '#to_hash' do
    before :each do
      File.stub :read => 'blah'
    end

    [:stopwords, :wordforms, :exceptions].each do |setting|
      it "collects #{setting} files from indices" do
        indices << index_double(setting => '/my/file/foo.txt')

        files.to_hash.should == {
          "#{setting}/foo.txt" => 'blah',
          'extra'              => "#{setting}/foo.txt"
        }
      end

      it "does not repeat same files for #{setting}" do
        indices << index_double(setting => '/my/file/foo.txt')
        indices << index_double(setting => '/my/file/foo.txt')

        files.to_hash.should == {
          "#{setting}/foo.txt" => 'blah',
          'extra'              => "#{setting}/foo.txt"
        }
      end

      it "accepts multiples files for #{setting}" do
        indices << index_double(
          setting => '/my/file/foo.txt /my/file/bar.txt')

        files.to_hash["#{setting}/foo.txt"].should == 'blah'
        files.to_hash["#{setting}/bar.txt"].should == 'blah'
        files.to_hash['extra'].split(';').should =~ [
          "#{setting}/foo.txt", "#{setting}/bar.txt"
        ]
      end
    end

    [:mysql_ssl_cert, :mysql_ssl_key, :mysql_ssl_ca].each do |setting|
      it "collects #{setting} files from sources" do
        indices << index_double(:sources => [
          source_double(setting => '/my/file/foo.txt')])

        files.to_hash.should == {
          "#{setting}/foo.txt" => 'blah',
          'extra'              => "#{setting}/foo.txt"
        }
      end

      it "does not repeat same files for #{setting}" do
        indices << index_double(:sources => [
          source_double(setting => '/my/file/foo.txt')])
        indices << index_double(:sources => [
          source_double(setting => '/my/file/foo.txt')])

        files.to_hash.should == {
          "#{setting}/foo.txt" => 'blah',
          'extra'              => "#{setting}/foo.txt"
        }
      end

      it "accepts multiples files for #{setting}" do
        indices << index_double(:sources => [
          source_double(setting => '/my/file/foo.txt /my/file/bar.txt')])

        files.to_hash["#{setting}/foo.txt"].should == 'blah'
        files.to_hash["#{setting}/bar.txt"].should == 'blah'
        files.to_hash['extra'].split(';').should =~ [
          "#{setting}/foo.txt", "#{setting}/bar.txt"
        ]
      end
    end
  end
end
