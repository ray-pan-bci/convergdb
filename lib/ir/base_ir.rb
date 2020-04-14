# Copyright © 2020 Beyondsoft Consulting, Inc.

# Permission is hereby granted, free of charge, to any person obtaining a copy of this software
# and associated documentation files (the “Software”), to deal in the Software without
# restriction, including without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all copies or
# substantial portions of the Software.

# THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
# BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
# DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

module ConvergDB
  # regex for common string validations
  module ValidationRegex
    # used for SQL identifiers such as domain, schema, relation, and attributes
    SQL_IDENTIFIER = /^[a-zA-Z]+\w{,127}$/

    # aws region in format ap-southeast-2
    AWS_REGION = /^\w+\-\w+\-\d+$/

    # source relation prefix is dot notated
    SOURCE_RELATION_PREFIX = /^[a-zA-Z]\w*(\.*[a-zA-Z]\w*){0,3}$/i

    # full relation name 4 identifiers dot notated
    FULL_RELATION_NAME = /^[a-z]+\w*(\.[a-z]+\w*){3}$/

    # dsd relation name
    DSD_RELATION_NAME = /^[a-zA-Z]\w*(\.*[a-zA-Z]\w*){2}$/i

    # dsd name scoped
    DSD_NAME_SCOPED = /^[a-zA-Z]\w*(\.*[a-zA-Z]\w*){0,2}$/i

    # service role for glue
    AWS_GLUE_SERVICE_ROLE = /^[a-zA-Z]+\w*$|^$/

    BOOLEAN_VALUE = /(^t$|^true$|^f$|^false$|^$)/i

    ATHENA_TABLE = /(^[a-zA-Z]+\w{,127}\.[a-zA-Z]+\w{,127}$|^$)/
  end

  # Base class for intermediate representations (IR).
  #
  # Each IR follows the same general pattern.
  #
  # IRs are created as trees of objects representing parent/child
  # relationships. These trees are created by a builder class which has
  # methods designed to complement the AST traversal order.
  #
  # resolve! method performs a lookup for any attributes of the object which
  # need to be set. Each :resolve! method is responsible for calling the
  # :resolve! method of it's children, if any.
  #
  # :validate method is called to perform a validation of the object. Each
  # :validate method is responsible for calling the :validate method of it's
  # children, if any. These methods should raise an exception if a validation
  # fails.
  #
  # :validate_string_attributes - method performs string validations based upon
  # the hash provided by :validation_regex:.
  #
  # :validation_regex - is a hash specific to each object, providing the
  # details of the regex match validation to be performed.
  #
  # :structure method returns a hash of the resolved attributes for a given
  # object. :structure is responsible for recursively calling the :structure
  # method of it's children, if any.
  #
  # :structure delivers the true IR.
  #
  # @abstract
  class BaseStructure
    # exposed for unit testing
    attr_accessor :parent

    # every class needs to return a resolved subtree representing
    # itself and it's descendants.
    # recursive calls to structure will come from parent.
    # recursive calls to child structures should be made by
    # this method when implemented.
    # @return [Hash] hash/array representation
    def structure
      raise "structure must be implemented in #{self.class}"
    end

    # resolves any references in the object
    # then calls child resolve methods
    def resolve!
      raise "resolve must be implemented in #{self.class}"
    end

    # validates any properties or attributes in the object
    # then calls child validate methods. raises errors along the way.
    def validate
      raise "validate must be implemented in #{self.class}"
    end

    # accepts a method of the current object as a parameter,
    # represented as a symbol. the return value of this function
    # is determined by prioritizing the value of the method in
    # the current object (if present) over the value of the
    # method in the parent object (if present). the result
    # may also be nil due to neither method having a value.
    # @param [Symbol] method symbol representation of the method name
    # @return [Object] current object value prioritized over parent
    def override_parent(method)
      self.send(method) || @parent.send(method)
    end

    # used for validating string parameters. pass in the
    # value to be tested along with the regex expression.
    # nil is an acceptable value if mandatory is not set to true.
    # note that this will return true if there is any match so
    # be specific with your pattern definition.
    # @param [String] str string to be tested
    # @param [Regexp] pattern regex pattern to match
    # @param [true, false] mandatory defaults to false
    # @return [true, false] indicates whether match was successful
    def valid_string_match?(str, pattern, mandatory = false)
      # puts "validating #{str} with pattern #{pattern}"
      unless mandatory == true
        return true unless str
      end
      return false unless str.class == String
      return false unless str =~ pattern
      true
    end
    
    def coerced_string_match?(str, pattern, mandatory = false)
      # puts "validating #{str} with pattern #{pattern}"
      unless mandatory == true
        return true unless str
      end
      return false unless str.to_s =~ pattern
      true
    end

    # validates all attributes defined by validation_regex
    def validate_string_attributes
      validation_regex.each_key do |m|
        t = valid_string_match?(
          self.send(m),
          validation_regex[m][:regex],
          validation_regex[m][:mandatory]
        )
        raise "#{self.class} error #{m} value #{self.send(m)}" unless t == true
      end
    end
    
    def is_convergdb_env_var?(var)
      var.match(/^CONVERGDB_.*/) ? true : false
    end
    
    def strip_var_ref(var_ref)
      var_ref.gsub('${env.', '').gsub('}', '')
    end
    
    def convergdb_env_var(var)
      if is_convergdb_env_var?(var)
        if ENV.key?(var)
          return ENV[var]
        else
          raise "environment variable #{var} does not exist."
        end
      else
        raise "environment variable #{var} must be prefixed with CONVERGDB_"
      end
    end
    
    def env_vars_in_this_string(string)
      return string.scan(/\$\{env\.\w+\}/).uniq
    end

    def apply_env_vars(input)
      return input if input.nil?
      tmp = input
      env_vars_in_this_string(input).each do |env_var|
        tmp.gsub!(
          env_var,
          convergdb_env_var(
            strip_var_ref(env_var)
          )
        )
      end
      return tmp
    end
    
    def apply_env_vars_to_attributes!(attributes)
      attributes.each do |attribute|
        self.send(
          "#{attribute}=", 
          apply_env_vars(self.send(attribute))
        )
      end
    end
  end
end
