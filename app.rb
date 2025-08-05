require 'sinatra'
require 'json'
require 'parser/current'
require 'set'
require 'rack/cors'

use Rack::Cors do
  allow do
    origins '*'
    resource '*', headers: :any, methods: [:post]
  end
end


post '/analyze' do
  content_type :json
  begin
    request_payload = JSON.parse(request.body.read)
    code = request_payload['code']

    buffer = Parser::Source::Buffer.new('(code)')
    buffer.source = code

    parser = Parser::CurrentRuby.new
    ast = parser.parse(buffer)

    result = analyze_ruby_code(ast, buffer)
    { success: true, result: result }.to_json
  rescue => e
    status 500
    { success: false, error: e.message }.to_json
  end
end

def analyze_ruby_code(ast, buffer)
  classes = []

  class_nodes = find_class_nodes(ast)

  if class_nodes.empty?
    # If no class is present, analyze top-level structures
    top_level_methods = []
    instance_vars = []
    local_vars = []
    method_calls = []
    conditionals = []

    walk_ast(ast) do |node|
      case node.type
      when :def
        method_name = node.children[0].to_s
        args = node.children[1].children.map { |arg| arg.children[0].to_s }
        method_line = node.location.name.line rescue nil

        m_instance_vars = []
        m_local_vars = []
        m_method_calls = []
        m_conditionals = []

        walk_ast(node) do |inner|
          case inner.type
          when :ivasgn
            line_number = inner.location&.name&.line rescue nil
            m_instance_vars << {
              name: inner.children[0].to_s,
              line_number: line_number
            }
          when :lvasgn
            line_number = inner.location&.name&.line rescue nil
            m_local_vars << {
              name: inner.children[0].to_s,
              line_number: line_number
            }
          when :send
            line_number = inner.location&.selector&.line rescue nil
            m_method_calls << {
              name: inner.children[1].to_s,
              line_number: line_number
            }
          when :if
            condition_src = buffer.source[inner.location.expression.begin_pos...inner.location.expression.end_pos].lines.first
            line_number = inner.location.expression.line rescue nil
            m_conditionals << {
              condition: condition_src.strip,
              line_number: line_number
            }
          end
        end

        top_level_methods << {
          name: method_name,
          arguments: args,
          line_number: method_line,
          instance_variables: m_instance_vars,
          local_variables: m_local_vars,
          method_calls: m_method_calls,
          conditionals: m_conditionals
        }
      end
    end

    return {
      classes: [],
      top_level: {
        methods: top_level_methods
      }
    }
  else
    # Process class-based structure
    class_nodes.each do |class_node|
      class_name = class_node.children[0].const_name
      inherits_from = class_node.children[1]&.const_name
      class_line = class_node.location.name.line rescue nil

      methods = []

      walk_ast(class_node) do |n|
        if n.type == :def
          method_name = n.children[0].to_s
          args = n.children[1].children.map { |arg| arg.children[0].to_s }
          method_line = n.location.name.line rescue nil

          instance_vars = []
          local_vars = []
          method_calls = []
          conditionals = []

          walk_ast(n) do |inner|
            case inner.type
            when :ivasgn
              line_number = inner.location&.name&.line rescue nil
              instance_vars << {
                name: inner.children[0].to_s,
                line_number: line_number
              }
            when :lvasgn
              line_number = inner.location&.name&.line rescue nil
              local_vars << {
                name: inner.children[0].to_s,
                line_number: line_number
              }
            when :send
              line_number = inner.location&.selector&.line rescue nil
              method_calls << {
                name: inner.children[1].to_s,
                line_number: line_number
              }
            when :if
              condition_src = buffer.source[inner.location.expression.begin_pos...inner.location.expression.end_pos].lines.first
              line_number = inner.location.expression.line rescue nil
              conditionals << {
                condition: condition_src.strip,
                line_number: line_number
              }
            end
          end

          methods << {
            name: method_name,
            arguments: args,
            line_number: method_line,
            instance_variables: instance_vars,
            local_variables: local_vars,
            method_calls: method_calls,
            conditionals: conditionals
          }
        end
      end

      classes << {
        class_name: class_name,
        inherits_from: inherits_from,
        line_number: class_line,
        methods: methods
      }
    end

    return { classes: classes }
  end
end




def walk_ast(node, &block)
  return unless node.is_a?(Parser::AST::Node)

  yield node
  node.children.each do |child|
    walk_ast(child, &block) if child.is_a?(Parser::AST::Node)
  end
end

def find_class_nodes(node)
  result = []
  walk_ast(node) do |n|
    result << n if n.type == :class
  end
  result
end

class Parser::AST::Node
  def const_name
    return nil unless type == :const

    parts = []
    node = self
    while node
      parts.unshift(node.children[1].to_s)
      node = node.children[0]
      break unless node.is_a?(Parser::AST::Node)
    end
    parts.join("::")
  end
end

puts "🚀 Sinatra Ruby analyzer is running on http://localhost:4567"


get '/' do
  content_type :json
  { message: "✅ Ruby Analyzer API is running." }.to_json
end
