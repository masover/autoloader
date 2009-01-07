autoload :Set, 'set'
autoload :Pathname, 'pathname'

module AutoLoader
  
  EXTENSIONS = %w{rb o}.map(&:freeze).freeze
  
  # We need some sort of inflection library.
  # Note: Sequel provides its own inflector, too...
  # This should be done in a more extensible way.
  def self.own_dependencies
    require 'extlib/string'
  rescue LoadError
    begin
      require 'active_support/inflector'
    rescue LoadError
      require 'rubygems'
      gem 'activesupport'
      require 'active_support/inflector'
    end
  end
  
  # Find a method that the object responds to, and execute that.
  # If no methods match, load dependencies and try again.
  def self._try_methods object, *methods
    method = methods.find {|m| object.respond_to? m}
    if method
      object.send method
    else
      nil
    end
  end
  def self.try_methods object, *methods
    self._try_methods(object, *methods) || (
      self.own_dependencies
      self._try_methods(object, *methods) || raise(NoMethodError, methods.first.to_s)
    )
  end
  
  # Semi-agnostic inflections.
  # Send patches, feel free to monkeypatch it, or
  # define your own camelize/underscore methods.
  def self.to_file_name string
    self.try_methods string, :to_const_path, :camelize
  end
  def self.to_const_name string
    self.try_methods string, :to_const_string, :underscore
  end
  
  
  def self.paths
    @paths ||= Set.new
  end
  
  def self.push *args
    args.each do
      self << args
    end
  end
  
  def self.<< path
    unless self.paths.include? path
      self.paths << path
      unless $:.include? path
        $: << path
      end
      
      self.update(:path => path)
    end
  end
  
  def self.update(options)
    if !options[:path]
      self.paths.each {|p| self.update(options.merge(:path => p))}
    else
      
      path = Pathname.new options[:path]
      parent = options[:parent]
      
      glob_path = parent.nil? ? path : path.join(self.to_file_name parent.name)
      
      EXTENSIONS.each do |ext|
        Pathname.glob(glob_path.join("*.#{ext}").to_s).each do |file|
          basename = file.basename(file.extname)
          
          camelized = self.to_const_name basename.to_s
          next unless camelized =~ /^[A-Z]\w*/
          
          req_path = file.parent.relative_path_from(path).join(basename).to_s
          
          if parent.nil?
            Object.autoload camelized, req_path
          else
            parent.autoload camelized, req_path
          end
        end
      end
    end
  end
  
  # Some syntactic sugar
  def self.included mod
    self.update(:parent => mod)
  end
end