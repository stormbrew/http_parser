require 'stringio'
require 'tempfile'
require 'strscan'

module Http
  # This is a native ruby implementation of the http parser. It is also
  # the reference implementation for this library. Later there will be one
  # written in C for performance reasons, and it will have to pass the same
  # specs as this one.
  class NativeParser
    # The HTTP method string used. Will always be a string and all-capsed.
    # Valid values are: "GET", "HEAD", "POST", "PUT", "DELETE".
    # Other values will cause an exception since then we don't know
    # whether the request has a body.
    attr_reader :method
    
    # The path given by the client as a string. No processing is done on
    # this and nearly anything is considered valid.
    attr_reader :path
    
    # The HTTP version of the request as an array of two integers.
    # [1,0] and [1,1] are the most likely values currently.
    attr_reader :version
    
    # A hash of headers passed to the server with the request. All
    # headers will be normalized to ALLCAPS_WITH_UNDERSCORES for
    # consistency's sake.
    attr_reader :headers
    
    # The body of the request as a stream object. May be either
    # a StringIO or a TempFile, depending on request length.
    attr_reader :body
    
    # The default set of parse options for the request.
    DefaultOptions = {
      # maximum length of an individual header line.
      :max_header_length => 10240, 
      # maximum number of headers that can be passed to the server
      :max_headers => 100,
      # the size of the request body before it will be spilled
      # to a tempfile instead of being stored in memory.
      :min_tempfile_size => 1048576,
      # the class to use to create and manage the temporary file.
      # Must conform to the same interface as the stdlib Tempfile class
      :tempfile_class => Tempfile,
    }
    
    # Regex used to match the Request-Line
    RequestLineMatch = %r{^([a-zA-Z]+) (.+) HTTP/([0-9]+)\.([0-9]+)\r?\n}
    # Regex used to match a header line. Lines suspected of
    # being headers are also checked against the HeaderContinueMatch
    # to deal with multiline headers
    HeaderLineMatch = %r{^([a-zA-Z-]+):[ \t]*([[:print:]]+)\r?\n}
    HeaderContinueMatch = %r{^[ \t]+([[:print:]]+)\r?\n}
    HeaderEndMatch = %r{^\r?\n}
    
    def initialize(options = DefaultOptions)
      @method = nil
      @path = nil
      @version = nil
      @headers = {}
      @body = nil
      @state = :request_line
      @options = DefaultOptions.merge(options)
    end
    
    # Returns true if the http method being parsed (if
    # known at this point in the parse) should have a body.
    # If the method hasn't been determined yet, returns false.
    def has_body?
      ["POST","PUT"].include?(@method)
    end
    
    # Takes a string and runs it through the parser. Note that
    # it does not consume anything it can't completely parse, so
    # you should always pass complete request chunks (lines or body data)
    # to this method. It's mostly for testing and convenience.
    # In practical use, you want to use parse!, which will remove parsed
    # data from the string you pass in.
    def parse(str)
      parse!(str.dup)
    end
    
    def parse_request_line(scanner)
      if (scanner.scan(RequestLineMatch))
        @method = scanner[1]
        @path = scanner[2]
        @version = [scanner[3].to_i, scanner[4].to_i]
    
        @state = :headers
        
        if (!["OPTIONS","GET","HEAD","POST","PUT","DELETE","TRACE","CONNECT"].include?(@method))
          raise Http::ParserError::NotImplemented
        end
      end
    end
    private :parse_request_line
    
    def parse_headers(scanner)
      if (scanner.scan(HeaderLineMatch))
        header = normalize_header(scanner[1])
        @headers[header] = scanner[2]
        @last_header = header
      elsif (@last_header && scanner.scan(HeaderContinueMatch))
        @headers[@last_header] << " " << scanner[1]
      elsif (scanner.scan(HeaderEndMatch))
        if (has_body?)
          if (!@headers["CONTENT_LENGTH"])
            raise ParserError::LengthRequired
          end
          @body_length = @headers["CONTENT_LENGTH"].to_i
          if (@body_length > 0)
            @state = :body
          else
            @state = :done
          end
          if (@body_length >= @options[:min_tempfile_size])
            @body = @options[:tempfile_class].new("http_parser")
            @body.unlink # unlink immediately so we don't rely on the caller to do it.
          else
            @body = StringIO.new
          end
        else
          @state = :done
        end
      end      
    end
    private :parse_headers
    
    def parse_body(scanner)
      remain = @body_length - @body.length
      addition = scanner.string[scanner.pos, remain]
      @body << addition
      
      scanner.pos += addition.length

      if (@body.length >= @body_length)
        @body.rewind
        @state = :done
      end
    end
    private :parse_body
    
    def parse_done(scanner)
      # do nothing, the parse is done.
    end
    private :parse_body
    
    # Consumes as much of str as it can and then removes it from str. This
    # allows you to iteratively pass data into the parser as it comes from
    # the client.
    def parse!(str)
      scanner = StringScanner.new(str)
      begin
        while (!scanner.eos?)
          start_pos = scanner.pos
          send(:"parse_#{@state}", scanner)
          if (scanner.pos == start_pos)
            # if we didn't move forward, we've run out of useful string so throw it back.
            return str
          end
        end
      ensure
        # clear out whatever we managed to scan.
        str[0, scanner.pos] = ""
      end
    end
    
    # Normalizes a header name to be UPPERCASE_WITH_UNDERSCORES
    def normalize_header(str)
      str.upcase.gsub('-', '_')
    end
    private :normalize_header
    
    # Returns true if the request is completely done.
    def done?
      @state == :done
    end
    
    # Returns true if the request has parsed the request-line (GET / HTTP/1.1) 
    def done_request_line?
      [:headers, :body, :done].include?(@state)
    end
    # Returns true if all the headers from the request have been consumed.
    def done_headers?
      [:body, :done].include?(@state)
    end
    # Returns true if the request's body has been consumed (really the same as done?)
    def done_body?
      done?
    end
  end
end