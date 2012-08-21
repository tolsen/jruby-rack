#--
# Copyright (c) 2010-2012 Engine Yard, Inc.
# Copyright (c) 2007-2009 Sun Microsystems, Inc.
# This source code is available under the MIT license.
# See the file LICENSE.txt for details.
#++

require File.expand_path('spec_helper', File.dirname(__FILE__) + '/../..')
require 'jruby/rack/response'

describe JRuby::Rack::Response do
  before :each do
    @status, @headers, @body = mock("status"), mock("headers"), mock("body")
    @headers.stub!(:[]).and_return nil
    @servlet_response = mock "servlet response"
    @response = JRuby::Rack::Response.new([@status, @headers, @body])
  end

  it "should return the status, headers and body" do
    @response.getStatus.should == @status
    @response.getHeaders.should == @headers
    @body.should_receive(:each).and_yield "hello"
    @response.getBody.should == "hello"
  end

  it "should write the status to the servlet response" do
    @status.should_receive(:to_i).and_return(200)
    @servlet_response.should_receive(:setStatus).with(200)
    @response.write_status(@servlet_response)
  end

  it "should write the headers to the servlet response" do
    @headers.should_receive(:each). # @headers.each do |k, v|
      and_yield("Content-Type", "text/html").
      and_yield("Content-Length", "20").
      and_yield("Server",  "Apache/2.2.x")
    @servlet_response.should_receive(:setContentType).with("text/html")
    @servlet_response.should_receive(:setContentLength).with(20)
    @servlet_response.should_receive(:addHeader).with("Server", "Apache/2.2.x")
    @response.write_headers(@servlet_response)
  end

  it "should write headers with multiple values multiple addHeader invocations" do
    @headers.should_receive(:each). # @headers.each do |k, v|
      and_yield("Content-Type", "text/html").
      and_yield("Content-Length", "20").
      and_yield("Set-Cookie",  %w(cookie1 cookie2))
    @servlet_response.should_receive(:setContentType).with("text/html")
    @servlet_response.should_receive(:setContentLength).with(20)
    @servlet_response.should_receive(:addHeader).with("Set-Cookie", "cookie1")
    @servlet_response.should_receive(:addHeader).with("Set-Cookie", "cookie2")
    @response.write_headers(@servlet_response)
  end

  it "should write headers whose value contains newlines as multiple addHeader invocations" do
    @headers.should_receive(:each).
      and_yield("Set-Cookie",  "cookie1\ncookie2")
    @servlet_response.should_receive(:addHeader).with("Set-Cookie", "cookie1")
    @servlet_response.should_receive(:addHeader).with("Set-Cookie", "cookie2")
    @response.write_headers(@servlet_response)
  end

  it "should write headers whose value contains newlines as multiple addHeader invocations when string doesn't respond to #each" do
    str = "cookie1\ncookie2"
    class << str; undef_method :each; end if str.respond_to?(:each)
    @headers.should_receive(:each).and_yield "Set-Cookie", str
    @servlet_response.should_receive(:addHeader).with("Set-Cookie", "cookie1")
    @servlet_response.should_receive(:addHeader).with("Set-Cookie", "cookie2")
    @response.write_headers(@servlet_response)
  end

  it "should call addIntHeader with integer value" do
    @headers.should_receive(:each).and_yield "Expires", 0
    @servlet_response.should_receive(:addIntHeader).with("Expires", 0)
    @response.write_headers(@servlet_response)
  end

  it "should call addDateHeader with date value" do
    time = Time.now - 1000
    @headers.should_receive(:each).and_yield "Last-Modified", time
    @servlet_response.should_receive(:addDateHeader).with("Last-Modified", time.to_i * 1000)
    @response.write_headers(@servlet_response)
  end

  it "should detect a chunked response when the Transfer-Encoding header is set" do
    @headers = { "Transfer-Encoding" => "chunked" }
    @response = JRuby::Rack::Response.new([@status, @headers, @body])
    @servlet_response.should_receive(:addHeader).with("Transfer-Encoding", "chunked")
    @response.write_headers(@servlet_response)
    @response.chunked?.should eql(true)
  end

  it "should write the status first, followed by the headers, and the body last" do
    @servlet_response.should_receive(:committed?).and_return false
    @response.should_receive(:write_status).ordered
    @response.should_receive(:write_headers).ordered
    @response.should_receive(:write_body).ordered
    @response.respond(@servlet_response)
  end

  it "should not write the status, the headers, or the body if the request was forwarded" do
    @servlet_response.should_receive(:committed?).and_return true
    @response.should_not_receive(:write_status)
    @response.should_not_receive(:write_headers)
    @response.should_not_receive(:write_body)
    @response.respond(@servlet_response)
  end

  it "#getBody should call close on the body if the body responds to close" do
    @body.should_receive(:each).ordered.and_yield "hello"
    @body.should_receive(:close).ordered
    @response.getBody.should == "hello"
  end

  describe "#write_body" do
    let(:stream) do
      StubOutputStream.new.tap do |stream|
        @servlet_response.stub!(:getOutputStream).and_return stream
      end
    end

    it "does not flush after write if Content-Length header is set" do
      @body.should_receive(:each).
        and_yield("hello").
        and_yield("there")
      @headers.should_receive(:[]).with('Content-Length').
        exactly(3).times.
        and_return("hellothere".size)
      @response.streamed?.should eql(false)
      stream.should_receive(:write).exactly(2).times
      stream.should_not_receive(:flush)

      @response.write_body(@servlet_response)
    end

    it "writes the body to the stream and flushes when the response is chunked" do
      @headers = { "Transfer-Encoding" => "chunked" }
      @response = JRuby::Rack::Response.new([@status, @headers, @body])
      @servlet_response.should_receive(:addHeader).with("Transfer-Encoding", "chunked")
      @response.write_headers(@servlet_response)
      @response.chunked?.should eql(true)
      @body.should_receive(:each).ordered.
        and_yield("hello").
        and_yield("there")
      stream.should_receive(:write).exactly(2).times
      stream.should_receive(:flush).exactly(2).times
      @response.write_body(@servlet_response)
    end

    it "writes the body to the servlet response" do
      @body.should_receive(:each).
        and_yield("hello").
        and_yield("there")

      stream.should_receive(:write).exactly(2).times

      @response.write_body(@servlet_response)
    end

    it "calls close on the body if the body responds to close" do
      @body.should_receive(:each).ordered.
        and_yield("hello").
        and_yield("there")
      @body.should_receive(:close).ordered
      stream.should_receive(:write).exactly(2).times

      @response.write_body(@servlet_response)
    end

    it "yields the stream to an object that responds to #call" do
      @body.should_receive(:call).and_return do |stream|
        stream.write("".to_java_bytes)
      end
      stream.should_receive(:write).exactly(1).times

      @response.write_body(@servlet_response)
    end

    it "does not yield the stream if the object responds to both #call and #each" do
      @body.stub!(:call)
      @body.should_receive(:each).and_yield("hi")
      stream.should_receive(:write)

      @response.write_body(@servlet_response)
    end

    it "writes the stream using a channel if the object responds to #to_channel" do
      channel = mock "channel"
      @body.should_receive(:to_channel).and_return channel
      read_done = false
      channel.should_receive(:read).exactly(2).times.and_return do |buf|
        if read_done
          -1
        else
          buf.put "hello".to_java_bytes
          read_done = true
          5
        end
      end
      stream.should_receive(:write)

      @response.write_body(@servlet_response)
    end
    
    it "streams a file using a channel if wrapped in body_parts", 
      :lib => [ :rails30, :rails31, :rails32 ] do
      require 'action_dispatch/http/response'
      
      path = File.expand_path('../../files/image.jpg', File.dirname(__FILE__))
      file = File.open(path, 'rb')
      headers = { 
        "Content-Disposition"=>"attachment; filename=\"image.jpg\"", 
        "Content-Transfer-Encoding"=>"binary", 
        "Content-Type"=>"image/jpeg" 
      }
      # we're emulating the body how rails returns it (for a file response)
      body = ActionDispatch::Response.new(200, headers, file)
      body = Rack::BodyProxy.new(body) { nil } if defined?(Rack::BodyProxy)
      # Rack::BodyProxy not available with Rails 3.0.x
      # with 3.2 there's even more wrapping with ActionDispatch::BodyProxy
      
      response = JRuby::Rack::Response.new [ 200, headers, body ]
      stream = self.stream
      response.should_receive(:transfer_channel).with do |ch, s|
        s.should == stream 
        ch.should be_a java.nio.channels.FileChannel
        ch.size.should == File.size(path)
      end

      response.write_body(@servlet_response)
    end
    
    it "uses #transfer_to to copy the stream if available" do
      channel = mock "channel"
      @body.should_receive(:to_channel).and_return channel
      channel.stub!(:size).and_return 10
      channel.should_receive(:transfer_to).with(0, 10, anything)
      stream.should be_kind_of(java.io.OutputStream)

      @response.write_body(@servlet_response)
    end

    it "writes the stream using a channel if the object responds to #to_inputstream" do
      @body.should_receive(:to_inputstream).and_return StubInputStream.new("hello")
      stream.should be_kind_of(java.io.OutputStream)

      @response.write_body(@servlet_response)
      stream.to_s.should == "hello"
    end
  end
end
