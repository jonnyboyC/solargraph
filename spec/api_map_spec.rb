require 'tmpdir'

describe Solargraph::ApiMap do
  before :all do
    @api_map = Solargraph::ApiMap.new
  end

  it "returns core methods" do
    pins = @api_map.get_methods('String')
    expect(pins.map(&:path)).to include('String#upcase')
  end

  it "returns core classes" do
    pins = @api_map.get_constants('')
    expect(pins.map(&:path)).to include('String')
  end

  it "indexes pins" do
    map = Solargraph::SourceMap.load_string(%(
      class Foo
        def bar
        end
      end
    ))
    @api_map.index map.pins
    pins = @api_map.get_path_pins('Foo#bar')
    expect(pins.length).to eq(1)
    expect(pins.first.path).to eq('Foo#bar')
  end

  it "finds methods from included modules" do
    map = Solargraph::SourceMap.load_string(%(
      module Mixin
        def mix_method
        end
      end
      class Foo
        include Mixin
        def bar
        end
      end
    ))
    @api_map.index map.pins
    pins = @api_map.get_methods('Foo')
    expect(pins.map(&:path)).to include('Mixin#mix_method')
  end

  it "finds methods from superclasses" do
    map = Solargraph::SourceMap.load_string(%(
      class Sup
        def sup_method
        end
      end
      class Sub < Sup
      end
    ))
    @api_map.index map.pins
    pins = @api_map.get_methods('Sub')
    expect(pins.map(&:path)).to include('Sup#sup_method')
  end

  it "checks method pin visibility" do
    map = Solargraph::SourceMap.load_string(%(
      class Foo
        private
        def bar
        end
      end
    ))
    @api_map.index map.pins
    pins = @api_map.get_methods('Foo')
    expect(pins.map(&:path)).not_to include('Foo#bar')
  end

  it "finds nested namespaces" do
    map = Solargraph::SourceMap.load_string(%(
      module Foo
        class Bar
        end
        class Baz
        end
      end
    ))
    @api_map.index map.pins
    pins = @api_map.get_constants('Foo')
    paths = pins.map(&:path)
    expect(paths).to include('Foo::Bar')
    expect(paths).to include('Foo::Baz')
  end

  it "finds nested namespaces within a context" do
    map = Solargraph::SourceMap.load_string(%(
      module Foo
        class Bar
          BAR_CONSTANT = 'bar'
        end
        class Baz
        end
      end
    ))
    @api_map.index map.pins
    pins = @api_map.get_constants('Bar', 'Foo')
    expect(pins.map(&:path)).to include('Foo::Bar::BAR_CONSTANT')
  end

  it "checks constant visibility" do
    map = Solargraph::SourceMap.load_string(%(
      module Foo
        FOO_CONSTANT = 'foo'
        private_constant :FOO_CONSTANT
      end
    ))
    @api_map.index map.pins
    pins = @api_map.get_constants('Foo', '')
    expect(pins.map(&:path)).not_to include('Foo::FOO_CONSTANT')
    pins = @api_map.get_constants('', 'Foo')
    expect(pins.map(&:path)).to include('Foo::FOO_CONSTANT')
  end

  it "includes Kernel methods in the root namespace" do
    @api_map.index []
    pins = @api_map.get_methods('')
    expect(pins.map(&:path)).to include('Kernel#puts')
  end

  it "gets instance methods for complex types" do
    @api_map.index []
    type = Solargraph::ComplexType.parse('String')
    pins = @api_map.get_complex_type_methods(type)
    expect(pins.map(&:path)).to include('String#upcase')
  end

  it "gets class methods for complex types" do
    @api_map.index []
    type = Solargraph::ComplexType.parse('Class<String>')
    pins = @api_map.get_complex_type_methods(type)
    expect(pins.map(&:path)).to include('String.try_convert')
  end

  it "checks visibility of complex type methods" do
    map = Solargraph::SourceMap.load_string(%(
      class Foo
        private
        def priv
        end
        protected
        def prot
        end
      end
    ))
    @api_map.index map.pins
    type = Solargraph::ComplexType.parse('Foo')
    pins = @api_map.get_complex_type_methods(type, 'Foo')
    expect(pins.map(&:path)).to include('Foo#prot')
    expect(pins.map(&:path)).not_to include('Foo#priv')
    pins = @api_map.get_complex_type_methods(type, 'Foo', true)
    expect(pins.map(&:path)).to include('Foo#prot')
    expect(pins.map(&:path)).to include('Foo#priv')
  end

  it "finds methods for duck types" do
    @api_map.index []
    type = Solargraph::ComplexType.parse('#foo, #bar')
    pins = @api_map.get_complex_type_methods(type)
    expect(pins.map(&:name)).to include('foo')
    expect(pins.map(&:name)).to include('bar')
  end

  it "adds Object instance methods to duck types" do
    api_map = Solargraph::ApiMap.new
    type = Solargraph::ComplexType.parse('#foo')
    pins = api_map.get_complex_type_methods(type)
    expect(pins.any?{|p| p.namespace == 'Object'}).to be(true)
  end

  it "finds methods for parametrized class types" do
    @api_map.index []
    type = Solargraph::ComplexType.parse('Class<String>')
    pins = @api_map.get_complex_type_methods(type)
    expect(pins.map(&:path)).to include('String.try_convert')
  end

  it "finds stacks of methods" do
    map = Solargraph::SourceMap.load_string(%(
      module Mixin
        def meth; end
      end
      class Foo
        include Mixin
        def meth; end
      end
      class Bar < Foo
        def meth; end
      end
    ))
    @api_map.index map.pins
    pins = @api_map.get_method_stack('Bar', 'meth')
    expect(pins.map(&:path)).to eq(['Bar#meth', 'Foo#meth', 'Mixin#meth'])
  end

  it "finds symbols" do
    map = Solargraph::SourceMap.load_string('sym = :sym')
    @api_map.index map.pins
    pins = @api_map.get_symbols
    expect(pins.map(&:name)).to include(':sym')
  end

  it "finds instance variables" do
    map = Solargraph::SourceMap.load_string(%(
      class Foo
        @cvar = ''
        def bar
          @ivar = ''
        end
      end
    ))
    @api_map.index map.pins
    pins = @api_map.get_instance_variable_pins('Foo', :instance)
    expect(pins.map(&:name)).to include('@ivar')
    expect(pins.map(&:name)).not_to include('@cvar')
    pins = @api_map.get_instance_variable_pins('Foo', :class)
    expect(pins.map(&:name)).not_to include('@ivar')
    expect(pins.map(&:name)).to include('@cvar')
  end

  it "finds class variables" do
    map = Solargraph::SourceMap.load_string(%(
      class Foo
        @@cvar = make_value
      end
    ))
    @api_map.index map.pins
    pins = @api_map.get_class_variable_pins('Foo')
    expect(pins.map(&:name)).to include('@@cvar')
  end

  it "finds global variables" do
    map = Solargraph::SourceMap.load_string('$foo = []')
    @api_map.index map.pins
    pins = @api_map.get_global_variable_pins
    expect(pins.map(&:name)).to include('$foo')
  end

  it "generates clips" do
    source = Solargraph::Source.load_string(%(
      class Foo
        def bar; end
      end
      Foo.new.bar
    ), 'my_file.rb')
    @api_map.map source
    clip = @api_map.clip_at('my_file.rb', Solargraph::Position.new(4, 15))
    expect(clip).to be_a(Solargraph::SourceMap::Clip)
  end

  it "searches the Ruby core" do
    @api_map.index []
    results = @api_map.search('Array#len')
    expect(results).to include('Array#length')
  end

  it "documents the Ruby core" do
    @api_map.index []
    docs = @api_map.document('Array')
    expect(docs).not_to be_empty
    expect(docs.map(&:path).uniq).to eq(['Array'])
  end

  it "catalogs changes" do
    workspace = Solargraph::Workspace.new 'workspace'
    s1 = Solargraph::Source.load_string('class Foo; end')
    @api_map.catalog(Solargraph::Bundle.new(workspace: workspace, opened: [s1]))
    expect(@api_map.get_path_pins('Foo')).not_to be_empty
    s2 = Solargraph::Source.load_string('class Bar; end')
    @api_map.catalog(Solargraph::Bundle.new(workspace: workspace, opened: [s2]))
    expect(@api_map.get_path_pins('Foo')).to be_empty
    expect(@api_map.get_path_pins('Bar')).not_to be_empty
  end

  it "checks attribute visibility" do
    source = Solargraph::Source.load_string(%(
      class Foo
        attr_reader :public_attr
        private
        attr_reader :private_attr
      end
    ))
    @api_map.map source
    pins = @api_map.get_methods('Foo')
    paths = pins.map(&:path)
    expect(paths).to include('Foo#public_attr')
    expect(paths).not_to include('Foo#private_attr')
    pins = @api_map.get_methods('Foo', visibility: [:private])
    paths = pins.map(&:path)
    expect(paths).not_to include('Foo#public_attr')
    expect(paths).to include('Foo#private_attr')
  end

  it "resolves superclasses qualified with leading colons" do
    code = %(
      class Sup
        def bar; end
      end
      module Foo
        class Sup < ::Sup; end
        class Sub < Sup
          def bar; end
        end
      end
      )
      api_map = Solargraph::ApiMap.new
      source = Solargraph::Source.load_string(code)
      api_map.map source
      pins = api_map.get_methods('Foo::Sub')
      paths = pins.map(&:path)
      expect(paths).to include('Foo::Sub#bar')
      expect(paths).to include('Sup#bar')
  end

  it "finds protected methods for complex types" do
    code = %(
      class Sup
        protected
        def bar; end
      end
      class Sub < Sup; end
      class Sub2 < Sub; end
    )
    api_map = Solargraph::ApiMap.new
    source = Solargraph::Source.load_string(code)
    api_map.map source
    pins = api_map.get_complex_type_methods(Solargraph::ComplexType.parse('Sub'), 'Sub')
    expect(pins.map(&:path)).to include('Sup#bar')
    pins = api_map.get_complex_type_methods(Solargraph::ComplexType.parse('Sub2'), 'Sub2')
    expect(pins.map(&:path)).to include('Sup#bar')
    pins = api_map.get_complex_type_methods(Solargraph::ComplexType.parse('Sup'), 'Sub')
    expect(pins.map(&:path)).to include('Sup#bar')
    pins = api_map.get_complex_type_methods(Solargraph::ComplexType.parse('Sup'), 'Sub2')
    expect(pins.map(&:path)).to include('Sup#bar')
  end

  it "ignores undefined superclasses when finding complex type methods" do
    code = %(
      class Sub < Sup; end
      class Sub2 < Sub; end
    )
    api_map = Solargraph::ApiMap.new
    source = Solargraph::Source.load_string(code)
    api_map.map source
    expect {
      api_map.get_complex_type_methods(Solargraph::ComplexType.parse('Sub'), 'Sub2')
    }.not_to raise_error
  end

  it "detects private constants according to context" do
    code = %(
      class Foo
        class Bar; end
        private_constant :Bar
      end
    )
    api_map = Solargraph::ApiMap.new
    source = Solargraph::Source.load_string(code)
    api_map.map source
    pins = api_map.get_constants('Foo', '')
    expect(pins.map(&:path)).not_to include('Bar')
    pins = api_map.get_constants('Foo', 'Foo')
    expect(pins.map(&:path)).to include('Foo::Bar')
  end

  it "catalogs requires" do
    api_map = Solargraph::ApiMap.new
    source1 = Solargraph::Source.load_string(%(
      class Foo; end
    ), 'workspace/lib/foo.rb')
    source2 = Solargraph::Source.load_string(%(
      require 'foo'
      require 'invalid'
    ), 'workspace/app.rb')
    workspace = Solargraph::Workspace.new 'workspace'
    bundle = Solargraph::Bundle.new(workspace: workspace, opened: [source1, source2])
    api_map.catalog bundle
    expect(api_map.unresolved_requires).to eq(['invalid'])
  end

  it "gets instance variables from superclasses" do
    source = Solargraph::Source.load_string(%(
      class Sup
        def foo
          @foo = 'foo'
        end
      end
      class Sub < Sup; end
    ))
    api_map = Solargraph::ApiMap.new
    api_map.map source
    pins = api_map.get_instance_variable_pins('Sub')
    expect(pins.map(&:name)).to include('@foo')
  end

  it "gets methods from extended modules" do
    source = Solargraph::Source.load_string(%(
      module Mixin
        def bar; end
      end
      class Sup
        extend Mixin
      end
    ))
    api_map = Solargraph::ApiMap.new
    api_map.map source
    pins = api_map.get_methods('Sup', scope: :class)
    expect(pins.map(&:path)).to include('Mixin#bar')
  end

  it "loads workspaces from directories" do
    api_map = Solargraph::ApiMap.load('spec/fixtures/workspace')
    expect(api_map.source_map('spec/fixtures/workspace/app.rb')).to be_a(Solargraph::SourceMap)
  end

  it "finds constants from included modules" do
    source = Solargraph::Source.load_string(%(
      module Mixin
        FOO = 'foo'
      end
      class Container
        include Mixin
      end
    ))
    api_map = Solargraph::ApiMap.new
    api_map.map source
    pins = api_map.get_constants('Container')
    expect(pins.map(&:path)).to include('Mixin::FOO')
  end

  it "sorts constants by name" do
    source = Solargraph::Source.load_string(%(
      module Foo
        AAB = 'aaa'
        class AAA; end
      end
    ))
    api_map = Solargraph::ApiMap.new
    api_map.map source
    pins = api_map.get_constants('Foo', '')
    expect(pins.length).to eq(2)
    expect(pins[0].name).to eq('AAA')
    expect(pins[1].name).to eq('AAB')
  end

  it "returns one pin for root methods" do
    source = Solargraph::Source.load_string(%(
      def sum1(a, b)
      end
      sum1()
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new
    api_map.map source
    pins = api_map.get_method_stack('', 'sum1')
    expect(pins.length).to eq(1)
    expect(pins.map(&:name)).to include('sum1')
  end

  it "detects method aliases with origins in other sources" do
    source1 = Solargraph::Source.load_string(%(
      class Sup
        # @return [String]
        def foo; end
      end
    ), 'workspace/source1.rb')
    source2 = Solargraph::Source.load_string(%(
      class Sub < Sup
        alias bar foo
      end
    ), 'workspace/source2.rb')
    api_map = Solargraph::ApiMap.new
    workspace = Solargraph::Workspace.new 'workspace'
    bundle = Solargraph::Bundle.new(workspace: workspace, opened: [source1, source2])
    api_map.catalog bundle
    pin = api_map.get_path_pins('Sub#bar').first
    expect(pin).not_to be_nil
    expect(pin.return_type.tag).to eq('String')
  end

  it "finds extended module methods" do
    source = Solargraph::Source.load_string(%(
      module MyModule
        def foo; end
      end
      module MyClass
        extend MyModule
      end
      ), 'test.rb')
    api_map = Solargraph::ApiMap.new
    api_map.map source
    pins = api_map.get_methods('MyClass', scope: :class)
    expect(pins.map(&:path)).to include('MyModule#foo')
  end

  it "merges source maps" do
    source1 = Solargraph::Source.load_string(%(
      class Foo
        def bar
        end
      end
    ))
    source2 = Solargraph::Source.load_string(%(
      class Foo
        def bar
          puts 'hello'
        end
      end
    ))
    api_map = Solargraph::ApiMap.new
    api_map.map source1
    first = api_map.source_map(nil)
    api_map.map source2
    second = api_map.source_map(nil)
    expect(first).to eq(second)
  end

  it "catalogs unsynchronized sources without rebuilding" do
    # @todo This spec determines whether the ApiMap merged without rebuilding
    #   by inspecting the internal #store attribute. See if there's a better
    #   way.
    source1 = Solargraph::Source.load_string(%(
      class Foo
        def bar; end
      end
      f
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new
    api_map.map source1
    store1 = api_map.send(:store)
    # This update should require a rebuild after it's synchronized because it
    # adds a local variable pin to the source map
    source2 = source1.start_synchronize Solargraph::Source::Updater.new(
      'test.rb',
      2,
      [
        Solargraph::Source::Change.new(
          Solargraph::Range.from_to(4, 7, 4, 7),
          'oo = Foo.new'
        )
      ]
    )
    api_map.map source2
    store2 = api_map.send(:store)
    # The unsynchronized source does not rebuild the store
    expect(store1).to be(store2)
    source3 = source2.finish_synchronize
    api_map.map source3
    store3 = api_map.send(:store)
    # The synchronized source rebuilds the store
    expect(store3).not_to be(store2)
  end

  it "qualifies namespaces from includes" do
    source = Solargraph::Source.load_string(%(
      module Foo
        class Bar; end
      end
      module Includer
        include Foo
      end
    ))
    api_map = Solargraph::ApiMap.new
    api_map.map source
    fqns = api_map.qualify('Bar', 'Includer')
    expect(fqns).to eq('Foo::Bar')
  end

  it "qualifies namespaces from root includes" do
    source = Solargraph::Source.load_string(%(
      module A
        module B
          module C
            def self.foo; end
          end
        end
      end

      include A
      B::C
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new
    api_map.map source
    fqns = api_map.qualify('B::C', '')
    expect(fqns).to eq('A::B::C')
  end

  it 'finds methods for classes that override constant assignments' do
    source = Solargraph::Source.load_string(%(
      class Foo
        Bar = String
        class Bar
          def baz; end
        end
      end
    ))
    api_map = Solargraph::ApiMap.new
    api_map.map source
    paths = api_map.get_methods('Foo::Bar').map(&:path)
    expect(paths).to include('Foo::Bar#baz')
  end

  it 'sets method alias visibility' do
    source = Solargraph::Source.load_string(%(
      class Foo
        private
        def bar; end
        alias baz bar
      end
    ))
    api_map = Solargraph::ApiMap.new
    api_map.map source
    pins = api_map.get_methods('Foo', visibility: [:public, :private])
    baz = pins.select { |pin| pin.name == 'baz' }.first
    expect(baz.visibility).to be(:private)
  end

  it 'finds constants in superclasses' do
    source = Solargraph::Source.load_string(%(
      class Foo
        Bar = 42
      end

      class Baz < Foo; end
    ))
    api_map = Solargraph::ApiMap.new
    api_map.map source
    pins = api_map.get_constants('Baz')
    expect(pins.map(&:path)).to include('Foo::Bar')
  end
end
