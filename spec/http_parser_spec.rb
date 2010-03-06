require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

require 'http/parser'

test_parsers = [Http::NativeParser]
test_parsers << Http::FastParser if Http.const_defined? :FastParser

describe Http::Parser do
  it "should be a reference to Http::NativeParser, or if present Http::FastParser" do
    Http.const_defined?(:Parser).should be_true
    if (Http.const_defined?(:FastParser))
      Http::Parser.should == Http::FastParser
    else
      Http::Parser.should == Http::NativeParser
    end
  end
end

test_parsers.each do |parser|
  describe parser do
    it "Should be able to parse a simple GET request" do
      p = parser.new
    	p.parse("GET / HTTP/1.1\r\n")
    	p.parse("Host: blah.com\r\n")
    	p.parse("Cookie: blorp=blah\r\n")
    	p.parse("\r\n")

      p.done?.should be_true
    	p.method.should == "GET"
    	p.version.should == [1,1]
    	p.path.should == "/"
    	p.headers["HOST"].should == "blah.com"
    	p.headers["COOKIE"].should == "blorp=blah"
  	end
  	
  	it "Should be able to parse a request with a body (ie. PUT)" do
  	  p = parser.new
    	p.parse("PUT / HTTP/1.1\r\n")
    	p.parse("Host: blah.com\r\n")
    	p.parse("Content-Type: text/text\r\n")
    	p.parse("Content-Length: 5\r\n")
    	p.parse("\r\n")
    	p.parse("stuff")

    	p.body.read.should == "stuff"
  	end
  	
  	it "Should be able to incrementally parse a request with arbitrarily placed string endings" do
  	  p = parser.new
    	s = "GET / HTTP/1.1\r\nHost:"
    	p.parse!(s)
    	s.should == "Host:"
    	p.method.should == "GET"
    	p.path.should == "/"
    	p.version.should == [1,1]
    	p.done_request_line?.should be_true
    	p.done_headers?.should be_false
    	p.done?.should be_false
    	
    	s << " blah.com\r\n"
    	p.parse!(s)
    	s.should == ""
    	p.headers["HOST"].should == "blah.com"
    	p.done_headers?.should be_false
    	p.done?.should be_false
    	
    	s << "\r\n"
    	p.parse!(s)
    	s.should == ""
    	p.done_headers?.should be_true
    	p.done?.should be_true
  	end
  end
end