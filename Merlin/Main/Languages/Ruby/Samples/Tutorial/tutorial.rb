# ****************************************************************************
#
# Copyright (c) Microsoft Corporation. 
#
# This source code is subject to terms and conditions of the Microsoft Public License. A 
# copy of the license can be found in the License.html file at the root of this distribution. If 
# you cannot locate the  Microsoft Public License, please send an email to 
# ironruby@microsoft.com. By using this source code in any fashion, you are agreeing to be bound 
# by the terms of the Microsoft Public License.
#
# You must not remove this notice, or any other, from this software.
#
#
# ****************************************************************************

require "stringio"

module Tutorial

    class Summary
      attr :title
      attr :description

      def initialize(title, desc)
        @title = title
        @description = desc
      end

      def body
        @description
      end

      def to_s
        @title
      end
    end

    class Task
        attr :description
        attr :setup
        attr :code
        attr :title
        attr :source_files # Files used by the task. The user might want to browse these files

        def initialize title, description, setup, code, source_files, &success_evaluator	                
            @title = title
            @description = description
            @setup = setup
            @code = code
            @source_files = source_files
            @success_evaluator = success_evaluator
            
        end

        def success?(interaction, show_errors=false)
            begin
                if @success_evaluator
                  return (@success_evaluator.call(interaction) ? true : false)
                else
                  old_verbose, $VERBOSE = $VERBOSE, nil                
                  begin
                    return eval(code_string, interaction.bind) == interaction.result
                  ensure
                    $VERBOSE = old_verbose
                  end
                end
            rescue => e
                warn %{success_evaluator raised error: #{e}} if show_errors
                return false
            end
        end
        
        def code_string
            c = code
            c = c.to_ary.join("\n") if c.respond_to? :to_ary
            c
        end
    end
    
    class Chapter
        attr :name, true # TODO - true is needed only to workaround data-binding bug
        attr :introduction, true
        attr :summary, true
        attr :tasks, true
        attr :next_item, true

        def initialize name, introduction = nil, summary = nil, tasks = [], next_item = nil
            @name = name
            @introduction = introduction
            @summary = summary
            @tasks = tasks
            @next_item = next_item
        end

        def to_s
            @name
        end
    end

    class Section
        attr :name, true # TODO - true is needed only to workaround data-binding bug
        attr :introduction, true
        attr :chapters, true

        def initialize name, introduction = nil, chapters = []
            @name = name
            @introduction = introduction
            @chapters = chapters
        end

        def to_s
            @name
        end    
    end

    class Tutorial
        attr :name
        attr :file
        attr :introduction, true
        attr :legal_notice, true
        attr :summary, true
        attr :sections, true

        def initialize name, file, introduction = nil, notice = nil, summary = nil, sections = []
            @name = name
            @file = file
            @introduction = introduction
            @legal_notice = notice
            @summary = summary
            @sections = sections
        end
        
        def to_s
            @name
        end
    end
    
    @@tutorials = {} unless class_variable_defined? :@@tutorials
    
    def self.add_tutorial(tutorial)
        @@tutorials[tutorial.file] = tutorial
    end

    def self.all
      Dir[File.expand_path("Tutorials/*_tutorial.rb", File.dirname(__FILE__))].each do |t|
        self.get_tutorial t unless File.directory?(t)
      end
      @@tutorials
    end

    def self.get_tutorial path = nil
        if not path
          all
          return @@tutorials.values.first
        end

        path = File.expand_path path
        if not @@tutorials.has_key? path
            require path
            raise "#{path} does not contains a tutorial definition" if not @@tutorials.has_key? path
        end
        
        return @@tutorials[path]
    end
    
    class ReplContext
        attr :scope
        attr :bind
        
        def initialize
            @partial_input = ""
            @scope = Object.new

            class << @scope            
                def include(*a)
                    self.class.instance_eval { include(*a) }
                end
                
                def to_s
                    "main (tutorial)"
                end
            end

            @bind = @scope.instance_eval { binding }
            
            # Allow the tutorial DSL to use i.bind.foo in the success-evaluator blocks
            def @bind.method_missing name, *args
                if args.empty?
                    eval name.to_s, self
                else
                    m = eval "method #{name.inspect}", self
                    m.call *args
                end
            end
        end
        
        def interact input
            # Redirect stdout. Note that this affects the entire process. If the program calls "puts"
            # for some reason on another thread, the user may not expect to see the output. But it is 
            # hard to distinguish between printing that the user initiated, and printing that the program 
            # itself is doing.
            output = StringIO.new
            old_stdout, $stdout = $stdout, output
            old_verbose, $VERBOSE = $VERBOSE, nil
            
            result = nil
            error = nil
            Thread.current[:evaluating_tutorial_input] = true
            
            begin
                result = eval(@partial_input + input.to_s, @bind) # TODO - to_s should not be needed here
            rescue Exception => error
                raise error if error.kind_of? SystemExit
            ensure
                $stdout = old_stdout
                Thread.current[:evaluating_tutorial_input] = nil
                $VERBOSE = old_verbose
            end

            if error.kind_of? SyntaxError and error.message =~ /unexpected (\$end|END_OF_FILE)/
                @partial_input += input
                @partial_input += "\n" unless input[input.size-1] == "\n" # TODO - input[-1] seems to cause IndexError
                InteractionResult.new(@bind, "", nil, nil, true)
            else
                @partial_input = ""
                InteractionResult.new(@bind, output.string, result, error)
            end
        end
        
        def reset_input
          @partial_input = ""
        end
    end
    
    class InteractionResult
        attr :bind
        attr :output
        attr :result
        attr :error
        
        def initialize(bind, output, result, error = nil, partial_input = false)
            @bind = bind
            @output = output
            @result = result
            @error = error
            @partial_input = partial_input
            
            raise "result should be nil if an exception was raised" if result and error
        end
        
        def to_s
            %{InteractionResult output=#{@output}, result=#{@error ? "(error)" : @result.inspect}, error=#{@error ? @error : "(none)"}}
        end
        
        def result
            raise "Interaction resulted in an exception" if error or @partial_input
            @result
        end
        
        def error
            raise "Partial input received" if @partial_input
            @error
        end
        
        def partial_input?
          @partial_input
        end
    end
    
    # Simple stub class for mocking.
    # TODO - move to a real mocking framework
    class Stub
        def initialize() @calls = [] end
        
        def respond_to?(name) true end
        
        def method_missing name, *args
            @calls << name
            Stub.new
        end
        
        def called?(name) @calls.include? name end
    end
    
    def self.stub() Stub.new end

  # Utility method to verify that a handler was added to an event
  # Since there is no easily visible side-effect to adding a handler, we monkey-patch the event
  # with a method that will set a flag attribute in a given module
  def self.snoop_add_handler tutorial_module, event_name, obj
    flag_name = event_name + "_flag"

    klass = class << tutorial_module
      self
    end
    klass.module_eval do
      attr_accessor(flag_name.to_sym)
    end
    tutorial_module.instance_variable_set(("@" + flag_name).to_sym, false)
    
    before_tutorial_name = "before_tutorial_" + event_name
    klass = class << obj
      self
    end
    if not klass.method_defined?(before_tutorial_name.to_sym)
      klass.instance_eval { alias_method(before_tutorial_name.to_sym, event_name.to_sym) }
      klass.class_eval %{
        def #{event_name} *a, &b
          if block_given?
            #{before_tutorial_name} *a, &b
            #{tutorial_module}.#{flag_name} = true
          else
            #{before_tutorial_name} *a
          end
        end
      }
    end
  end
end

class Object
    def tutorial name
        raise "Only one tutorial can be under creation at a time" if Thread.current[:tutorial]
        caller[0] =~ /\A(.*):[0-9]+/
        tutorial_file = $1
        t = Tutorial::Tutorial.new name, tutorial_file
        Thread.current[:tutorial] = t
        Thread.current[:prev_chapter] = nil

        yield

        Tutorial.add_tutorial t
        Thread.current[:tutorial] = nil
    end

    def introduction intro
        if Thread.current[:chapter]
            Thread.current[:chapter].introduction = intro
        elsif Thread.current[:section]
            Thread.current[:section].introduction = intro
        elsif Thread.current[:tutorial]
            Thread.current[:tutorial].introduction = intro
        else
            raise "introduction should only be used within a tutorial definition"
        end
    end
    
    def legal notice
        raise "legal should only be used within a tutorial definition" unless Thread.current[:tutorial]
        Thread.current[:tutorial].legal_notice = notice
    end
    
    def summary s
        s = if s.kind_of?(String)
              Tutorial::Summary.new nil, s 
            else
              opts = {:title => "Section complete!"}.merge(s)
              Tutorial::Summary.new opts[:title], opts[:body]
            end
        if Thread.current[:chapter]
            Thread.current[:chapter].summary = s
        elsif Thread.current[:tutorial]
            Thread.current[:tutorial].summary = s
        else
            raise "summary should only be used within a tutorial or chapter definition"
        end
    end
        
    def section name
        raise "Only one section can be under creation at a time" if Thread.current[:section]
        section = Tutorial::Section.new name
        Thread.current[:section] = section
        if Thread.current[:prev_chapter]
            Thread.current[:prev_chapter].next_item = section
        end

        yield

        Thread.current[:tutorial].sections << section
        Thread.current[:section] = nil
    end

    def chapter name
        raise "Only one chapter can be under creation at a time" if Thread.current[:chapter]
        chapter = Tutorial::Chapter.new name
        Thread.current[:chapter] = chapter
        if Thread.current[:prev_chapter]
            Thread.current[:prev_chapter].next_item = chapter
        end

        yield

        Thread.current[:section].chapters << chapter
        Thread.current[:prev_chapter] = chapter
        Thread.current[:chapter] = nil
    end

    def task(options, &success_evaluator)
        options = {}.merge(options)
        Thread.current[:chapter].tasks << Tutorial::Task.new(
          options[:title], options[:body], options[:setup], options[:code], options[:source_files], &success_evaluator)
    end

    # This represents an operation that consists of several closely realated task. It is useful to have
    # direct support for this so that the UI can better support it (by showing all the descriptions on the same
    # page)
    def multi_step_task(name, *tasks, &success_evaluator)
        raise NotImplementedError
    end
end

class String
  def strip_margin
    /( *)\w/ =~ self
    match = $1
    gsub(/^#{match}/, "")
  end
end