module Hubble::Backend
  class Memory
    def initialize
      @reports = []
      @fail    = false
    end

    attr_accessor :reports

    def fail!
      @fail = true
    end

    def report(data)
      if @fail
        fail
      end

      @reports << data
    end
  end
end
