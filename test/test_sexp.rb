$TESTING = true

if ENV["COV"]
  require "simplecov"
  SimpleCov.start do
    add_filter "lib/sexp_processor"
    add_filter "test"
  end
  warn "Running simplecov"
end

require "minitest/autorun"
require "minitest/hell" # beat these up
require "minitest/benchmark" if ENV["BENCH"]
require "sexp_processor"
require "sexp"
require "strict_sexp" if ENV["STRICT_SEXP"]
require "stringio"
require "pp"

def pyramid_sexp max
  # s(:array,
  #   s(:array, s(:s, 1)),
  #   s(:array, s(:s, 1), s(:s, 2)),
  #   ...
  #   s(:array, s(:s, 1), s(:s, 2), ... s(:s, max-1)))

  s(:array,
    *(1...max).map { |n|
      s(:array, *(1..n).map { |m|
          s(:s, m) })})
end

class SexpTestCase < Minitest::Test
  prove_it! # require an assertion in every test

  M  = Sexp::Matcher
  MC = Sexp::MatchCollection
  MR = Sexp::MatchResult

  CLASS_SEXP = s(:class, :cake, nil,
                 s(:defn, :foo, s(:args), s(:add, :a, :b)),
                 s(:defn, :bar, s(:args), s(:sub, :a, :b)))

  def skip_if_strict n = 1
    strict = ENV["STRICT_SEXP"].to_i

    skip "Can't pass on STRICT_SEXP mode" if strict >= n
  end

  # KEY for regex tests
  # :a == no change
  # :b == will change (but sometimes ONLY once)
  # :c == change to

  def assert_equal3 x, y
    skip_if_strict

    assert_operator x, :===, y
  end

  def refute_equal3 x, y
    refute_operator x, :===, y
  end

  def assert_pretty_print expect, input
    assert_equal expect, input.pretty_inspect.chomp
  end

  def assert_inspect expect, input
    assert_equal expect, input.inspect
  end

  def assert_search count, sexp, pattern
    assert_equal count, sexp.search_each(pattern).count
  end

  def assert_satisfy pattern, sexp
    assert_operator pattern, :satisfy?, sexp
  end

  def refute_satisfy pattern, sexp
    refute_operator pattern, :satisfy?, sexp
  end
end # class SexpTestCase

class MatcherTestCase < SexpTestCase
  def self.abstract_test_case! klass=self # REFACTOR: push this up to minitest
    extend Module.new {
      define_method :run do |*args|
        super(*args) unless self == klass
      end
    }
  end

  abstract_test_case!

  def matcher
    raise "Subclass responsibility"
  end

  def inspect_str
    raise "Subclass responsibility"
  end

  def pretty_str
    inspect_str
  end

  def sexp
    s(:a)
  end

  def bad_sexp
    s(:b)
  end

  def test_satisfy_eh
    assert_equal3 matcher, sexp
  end

  def test_satisfy_eh_fail
    skip "not applicable" unless bad_sexp
    refute_equal3 matcher, bad_sexp
  end

  def test_greedy
    refute_operator matcher, :greedy?
  end

  def test_inspect
    assert_inspect inspect_str, matcher
  end

  def test_pretty_print
    assert_pretty_print pretty_str, matcher
  end
end # class MatcherTestCase

class TestSexp < SexpTestCase # ZenTest FULL
  def setup
    super
    @sexp_class = Object.const_get(self.class.name[4..-1])
    @processor = SexpProcessor.new
    @sexp = @sexp_class.new(1, 2, 3)
    @basic_sexp = s(:lasgn, :var, s(:lit, 42).line(1)).line(1)
    @complex_sexp = s(:block,
                      s(:lasgn, :foo, s(:str, "foo").line(1)).line(1),
                      s(:if, s(:and, s(:true).line(2), s(:lit, 1).line(2)).line(2),
                        s(:if, s(:lvar, :foo).line(3),
                          s(:str, "bar").line(3),
                          nil).line(3),
                        s(:true).line(5)).line(2)).line(1)

    @re = s(:lit, 42)
    @bad1 = s(:lit, 24)
    @bad1 = s(:blah, 42)
  end

  def assert_from_array exp, input
    assert_equal exp, Sexp.from_array(input)
  end

  def test_class_from_array
    assert_from_array s(),                            []
    assert_from_array s(:s),                          [:s]
    assert_from_array s(:s, s(:m)),                   [:s, [:m]]
    assert_from_array s(:s, s(:m)),                   [:s, s(:m)]
    assert_from_array s(:s, s(:m, [:not_converted])), [:s, s(:m, [:not_converted])]
  end

  def test_compact
    input = s(:a, nil, :b)

    actual = input.compact

    assert_equal s(:a, :b), actual
    assert_same input, actual # returns mutated result
  end

  def test_array_type_eh
    capture_io do # HACK
      assert_equal false, @sexp.array_type?
      @sexp.unshift :array
      assert_equal true, @sexp.array_type?
    end
  end

  def test_each_of_type
    # TODO: huh... this tests fails if top level sexp :b is removed
    @sexp = s(:b, s(:a, s(:b, s(:a), :a, s(:b, :a), s(:b, s(:a)))))
    count = 0
    @sexp.each_of_type :a do
      count += 1
    end
    assert_equal(3, count, "must find 3 a's in #{@sexp.inspect}")
  end

  def test_equals2_array
    refute_equal @sexp, [1, 2, 3]        # Sexp == Array
    assert_raises Minitest::Assertion do # Array == Sexp.
      refute_equal [1, 2, 3], @sexp      # This is a bug in ruby:
    end
    # TODO: test if it is calling to_ary first? seems not to
  end

  def test_equals2_not_body
    sexp2 = s(1, 2, 5)
    refute_equal(@sexp, sexp2)
  end

  def test_equals2_sexp
    sexp2 = s(1, 2, 3)
    if @sexp.class == Sexp then
      skip "Not applicable to this target."
    else
      refute_equal(@sexp, sexp2)
    end
  end

  def test_equal3_full_match
    assert_equal3 s(),         s()             # 0
    assert_equal3 s(:blah),    s(:blah)        # 1
    assert_equal3 s(:a, :b),   s(:a, :b)       # 2
    assert_equal3 @basic_sexp, @basic_sexp.dup # deeper structure
  end

  def test_equal3_mismatch
    refute_equal3 s(),                      s(:a)
    refute_equal3 s(:a),                    s()
    refute_equal3 s(:blah1),                s(:blah2)
    refute_equal3 s(:a),                    s(:a, :b)
    refute_equal3 s(:a, :b),                s(:a)
    refute_equal3 s(:a1, :b),               s(:a2, :b)
    refute_equal3 s(:a, :b1),               s(:a, :b2)
    refute_equal3 @basic_sexp,              @basic_sexp.dup.push(42)
    refute_equal3 @basic_sexp.dup.push(42), @basic_sexp
  end

  def test_equal3_subset_match
    assert_match  s{s(:a)},      s(s(:a), s(:b))                  # left - =~
    assert_equal3 s{s(:a)},      s(s(:a), s(:b))                  # left - ===
    assert_equal3 s{s(:a)},      s(:blah, s(:a   ), s(:b))        # mid 1
    assert_equal3 s{s(:a, 1)},   s(:blah, s(:a, 1), s(:b))        # mid 2
    assert_equal3 s{s(:a)},      s(:blah, s(:blah, s(:a)))        # left deeper
  end

  def test_equalstilde_fancy
    assert_match s{ s(:b) }, s(:a, s(:b), :c)
    assert_match s(:a, s(:b), :c), s{ s(:b) }

    e = assert_raises ArgumentError do
      s(:b) =~ s(:a, s(:b), :c)
    end
    assert_equal "Not a pattern", e.message

    e = assert_raises ArgumentError do
      s(:a, s(:b), :c) =~ s(:b)
    end
    assert_equal "Not a pattern", e.message
  end

  def test_equalstilde_plain
    s{ s(:re) } =~ s(:data) # pattern on LHS
    s(:data) =~ s{ s(:re) } # pattern on RHS

    e = assert_raises ArgumentError do
      s(:re) =~ s(:data)    # no pattern
    end

    assert_equal "Not a pattern", e.message
  end

  def test_find_and_replace_all
    skip_if_strict 2

    @sexp    = s(:a, s(:a, :b, s(:a, :b), s(:a), :b, s(:a, s(:a))))
    expected = s(:a, s(:a, :a, s(:a, :a), s(:a), :a, s(:a, s(:a))))

    @sexp.find_and_replace_all(:b, :a)

    assert_equal(expected, @sexp)
  end

  def assert_gsub exp, sexp, from, to
    assert_equal exp, sexp.gsub(from, to)
  end

  def test_gsub
    assert_gsub s(:c),        s(:b),        s(:b), s(:c)
    assert_gsub s(:a),        s(:a),        s(:b), s(:c)
    assert_gsub s(:a, s(:c)), s(:a, s(:b)), s(:b), s(:c)
  end

  def test_gsub_empty
    assert_gsub s(:c), s(), s(), s(:c)
  end

  def test_gsub_multiple
    assert_gsub s(:a, s(:c), s(:c)),        s(:a, s(:b), s(:b)),        s(:b), s(:c)
    assert_gsub s(:a, s(:c), s(:a, s(:c))), s(:a, s(:b), s(:a, s(:b))), s(:b), s(:c)
  end

  def test_gsub_matcher
    assert_gsub s(:a, :b, :c),        s(:a, s(:b, 42), :c),        s{ s(:b, _) }, :b
    assert_gsub s(:a, s(:b), :c),     s(:a, s(:b), :c),            s{ s(:b, _) }, :b
    assert_gsub s(:a, s(:c, :b), :d), s(:a, s(:c, s(:b, 42)), :d), s{ s(:b, _) }, :b
    assert_gsub s(:a, s(:q), :c),     s(:a, s(:q), :c),            s{ s(:b, _) }, :b
  end

  def with_env key
    old_val, ENV[key] = ENV[key], "1"
    yield
  ensure
    ENV[key] = old_val
  end

  def with_verbose &block
    with_env "VERBOSE", &block
  end

  def with_debug &block
    with_env "DEBUG", &block
  end

  def test_inspect
    k = @sexp_class
    n = k.name[0].chr.downcase
    assert_equal("#{n}()",
                 k.new().inspect)
    assert_equal("#{n}(:a)",
                 k.new(:a).inspect)
    assert_equal("#{n}(:a, :b)",
                 k.new(:a, :b).inspect)
    assert_equal("#{n}(:a, #{n}(:b))",
                 k.new(:a, k.new(:b)).inspect)

    with_verbose do
      assert_equal("#{n}().line(42)",
                   k.new().line(42).inspect)
      assert_equal("#{n}(:a).line(42)",
                   k.new(:a).line(42).inspect)
      assert_equal("#{n}(:a, :b).line(42)",
                   k.new(:a, :b).line(42).inspect)
      assert_equal("#{n}(:a, #{n}(:b).line(43)).line(42)",
                   k.new(:a, k.new(:b).line(43)).line(42).inspect)
    end
  end

  def test_line
    assert_nil @sexp.line
    assert_equal 1, @basic_sexp.line
    assert_equal 1, @complex_sexp.line
  end

  def test_line_max
    assert_nil @sexp.line_max
    assert_equal 1, @basic_sexp.line_max
    assert_equal 5, @complex_sexp.line_max
  end

  def test_mass
    assert_equal 1, s(:a).mass
    assert_equal 3, s(:a, s(:b), s(:c)).mass

    s = s(:iter,
          s(:call, nil, :a, s(:arglist, s(:lit, 1))),
          s(:lasgn, :c),
          s(:call, nil, :d, s(:arglist)))

    assert_equal 7, s.mass
  end

  def test_mass_auto_shift
    assert_equal 1, s(:a).mass
    assert_equal 3, s(s(:b), s(:c)).mass

    s = s(s(:call, nil, :a, s(:arglist, s(:lit, 1))),
          s(:lasgn, :c),
          s(:call, nil, :d, s(:arglist)))

    assert_equal 7, s.mass
  end

  def test_mass_huge
    max = 100
    sexp = pyramid_sexp max

    exp = (max*max + max)/2 # pyramid number 1+2+3+...+m

    assert_equal exp, sexp.mass
  end

  def test_method_missing
    skip_if_strict 3

    capture_io do
      assert_nil @sexp.not_there
      assert_equal s(:lit, 42), @basic_sexp.lit
    end
  end

  def test_method_missing_missing
    skip_if_strict 3
    skip "debugging for now" if ENV["DEBUG"]

    assert_silent do
      assert_nil @basic_sexp.missing
    end
  end

  def test_method_missing_missing_debug
    skip_if_strict 3

    exp = /#{Regexp.escape @basic_sexp.to_s}.method_missing\(:missing\) => nil from/

    with_debug do
      assert_output "", exp do
        assert_nil @basic_sexp.missing
      end
    end
  end

  def test_method_missing_hit_debug_verbose
    skip_if_strict 3

    with_debug do
      with_verbose do
        exp = /#{Regexp.escape @basic_sexp.to_s}.method_missing\(:lit\) from/

        assert_output "", exp do
          assert_equal s(:lit, 42), @basic_sexp.lit
        end
      end
    end
  end

  def test_method_missing_ambigious
    skip_if_strict 3

    assert_raises NoMethodError do
      pirate = s(:says, s(:arrr!), s(:arrr!), s(:arrr!))
      pirate.arrr!
    end
  end

  def test_method_missing_deep
    skip_if_strict 3

    capture_io do
      sexp = s(:blah, s(:a, s(:b, s(:c, :yay!))))
      assert_equal(s(:c, :yay!), sexp.a.b.c)
    end
  end

  def test_method_missing_delete
    skip_if_strict 3

    sexp = s(:blah, s(:a, s(:b, s(:c, :yay!))))

    capture_io do
      assert_equal(s(:c, :yay!), sexp.a.b.c(true))
      assert_equal(s(:blah, s(:a, s(:b))), sexp)
    end
  end

  def test_pretty_print
    assert_pretty_print("s()",
                        s())
    assert_pretty_print("s(:a)",
                        s(:a))
    assert_pretty_print("s(:a, :b)",
                        s(:a, :b))
    assert_pretty_print("s(:a, s(:b))",
                        s(:a, s(:b)))
  end

  def test_sexp_body
    assert_equal [2, 3], @sexp.sexp_body
  end

  def test_shift
    skip "https://github.com/MagLev/maglev/issues/250" if maglev?

    assert_equal(1, @sexp.shift)
    assert_equal(2, @sexp.shift)
    assert_equal(3, @sexp.shift)

    assert_raises(RuntimeError) do
      @sexp.shift
    end
  end

  def test_deep_clone
    @sexp    = s(:a, 1, 2, s(:b, 3, 4), 5, 6)
    backup = @sexp.deep_clone
    refute_same @sexp, backup, "deep clone is broken again?"
    assert_equal @sexp, backup, "deep clone is broken again?"
  end

  def test_structure
    @sexp    = s(:a, 1, 2, s(:b, 3, 4), 5, 6)
    backup = @sexp.deep_clone
    refute_same @sexp, backup, "deep clone is broken again?"
    assert_equal @sexp, backup, "deep clone is broken again?"
    expected = s(:a, s(:b))

    assert_equal(expected, @sexp.structure)
    assert_equal(backup, @sexp)
  end

  def test_structure_deprecated
    exp_err = "NOTE: form s(s(:subsexp)).structure is deprecated. Removing in 5.0\n"

    assert_output "", exp_err do
      sexp = s(s(:subsexp))
      act = sexp.structure

      assert_equal s(:bogus, s(:subsexp)), act
    end
  end

  def test_sub
    assert_equal s(:c),               s(:b).               sub(s(:b), s(:c))
    assert_equal s(:a, s(:c), s(:b)), s(:a, s(:b), s(:b)). sub(s(:b), s(:c))
    assert_equal s(:a, s(:c), s(:a)), s(:a, s(:b), s(:a)). sub(s(:b), s(:c))
  end

  def test_sub_miss
    assert_equal s(:a),               s(:a).        sub(s(:b), s(:c))
    assert_equal s(:a, s(:c)),        s(:a, s(:c)). sub(s(:b), s(:c))
  end

  def test_sub_empty
    assert_equal s(:c),               s().          sub(s(), s(:c))
  end

  def assert_sub exp, sexp, from, to
    assert_equal exp, sexp.sub(from, to)
  end

  def test_sub_matcher
    assert_sub s(:c),               s(:b),               s{ s(:b) }, s(:c)
    assert_sub s(:a, s(:c), s(:b)), s(:a, s(:b), s(:b)), s{ s(:b) }, s(:c)
    assert_sub s(:a, s(:c), s(:a)), s(:a, s(:b), s(:a)), s{ s(:b) }, s(:c)

    assert_sub s(:a, :b, :c),        s(:a, s(:b, 42), :c),        s{ s(:b, _) }, :b
    assert_sub s(:a, s(:b), :c),     s(:a, s(:b), :c),            s{ s(:b, _) }, :b
    assert_sub s(:a, s(:c, :b), :d), s(:a, s(:c, s(:b, 42)), :d), s{ s(:b, _) }, :b
    assert_sub s(:a, s(:q), :c),     s(:a, s(:q), :c),            s{ s(:b, _) }, :b
  end

  def test_sub_structure
    assert_sub s(:a, s(:c, s(:b))), s(:a, s(:b)), s(:b), s(:c, s(:b))
  end

  def test_sexp_type_eq
    sexp = s(:bad_type, 42)

    sexp.sexp_type = :good_type

    assert_equal s(:good_type, 42), sexp
  end

  def test_sexp_body_eq
    sexp = s(:type, 42)

    sexp.sexp_body = [1, 2, 3]

    assert_equal s(:type, 1, 2, 3), sexp
  end

  def test_to_a
    assert_equal([1, 2, 3], @sexp.to_a)
  end

  def test_to_s
    test_inspect
  end

  def test_each_sexp
    result = []
    @basic_sexp.each_sexp { |_, val| result << val }
    assert_equal [42], result
  end

  def test_each_sexp_without_block
    assert_kind_of Enumerator, @basic_sexp.each_sexp
    assert_equal [42], @basic_sexp.each_sexp.map { |_, n| n }
  end

  def test_depth
    assert_equal 1, s(:a).depth
    assert_equal 2, s(:a, s(:b)).depth
    assert_equal 3, s(:a, s(:b1, s(:c)), s(:b2)).depth
    assert_equal 5, s(:a, s(:b, s(:c, s(:d, s(:e))))).depth
  end

  def test_deep_each
    result = []
    @complex_sexp.deep_each { |s| result << s if s.sexp_type == :if }
    assert_equal [:if, :if], result.map { |k, _| k }
  end

  def test_deep_each_without_block
    assert_kind_of Enumerator, @complex_sexp.deep_each
    assert_equal [:if, :if], @complex_sexp.deep_each.select { |s, _| s == :if }.map { |k, _| k }
  end

  def test_unary_not
    skip "TODO?"
    assert_equal M::Not.new(M.q(:a)), s{ !s(:a) }
  end

  def test_unary_not_outside
    skip "TODO?"
    assert_equal M::Not.new(s(:a)), !s(:a)
  end
end # TestSexp

class TestSexpMatcher < SexpTestCase
  def test_cls_s
    assert_equal M.q(:x), s{ s(:x) }
  end

  def test_cls_underscore
    assert_equal M::Wild.new, s{ _ }
  end

  def test_cls_underscore3
    assert_equal M::Remaining.new, s{ ___ }
  end

  def test_cls_include
    assert_equal M::Include.new(:a), s{ include(:a) }
  end

  def test_cls_atom
    assert_equal M::Atom.new, s{ atom }
  end

  def test_cls_any
    assert_equal M::Any.new(M.q(:a), M.q(:b)), s{ any(s(:a), s(:b)) }
  end

  def test_cls_all
    assert_equal M::All.new(M.q(:a), M.q(:b)), s{ all(s(:a), s(:b)) }
  end

  def test_cls_not_eh
    assert_equal M::Not.new(M.q(:a)), s{ not?(s(:a)) }
  end

  def test_cls_child
    assert_equal M::Child.new(M.q(:a)), s{ child(s(:a)) }
  end

  def test_cls_t
    assert_equal M::Type.new(:a), s{ t(:a) }
  end

  def test_cls_m
    assert_equal M::Pattern.new(/a/), s{ m(/a/) }
    assert_equal M::Pattern.new(/\Aa\Z/), s{ m(:a) }
  end

  def test_amp
    m = s{ s(:a) & s(:b) }
    e = M::All.new(M.q(:a), M.q(:b))

    assert_equal e, m
  end

  def test_pipe
    m = s{ s(:a) | s(:b) }
    e = M::Any.new(M.q(:a), M.q(:b))

    assert_equal e, m
  end

  def test_unary_minus
    assert_equal M::Not.new(M.q(:a)), s{ -s(:a) }
  end

  def test_rchevron
    assert_equal M::Sibling.new(M.q(:a), M.q(:b)), s{ s(:a) >> s(:b) }
  end

  def test_greedy_eh
    refute_operator s{ s(:a) }, :greedy?
  end

  def test_inspect
    assert_inspect "q(:a)", s{ s(:a) }
  end

  def test_pretty_print
    assert_pretty_print "q(:a)", s{ s(:a) }
  end
end # class TestSexpMatcher

class TestWild < MatcherTestCase
  def matcher
    s{ _ }
  end

  def bad_sexp
    nil
  end

  def inspect_str
    "_"
  end

  def test_wild_satisfy_eh # TODO: possibly remove
    w = Sexp::Wild.new

    assert_satisfy w, :a
    assert_satisfy w, 1
    assert_satisfy w, nil
    assert_satisfy w, []
    assert_satisfy w, s()
  end

  def test_wild_search # TODO: possibly remove
    sexp = CLASS_SEXP.dup

    assert_search 1, s(:add, :a, :b), s{ s(:add, _, :b) }
    assert_search 1, sexp,            s{ s(:defn, :bar, _, _) }
    assert_search 2, sexp,            s{ s(:defn, _, _, s(_, :a, :b) ) }
    assert_search 1, s(:a, s()),      s{ s(:a, _) }
    assert_search 1, s(:a, :b, :c),   s{ s(_, _, _) }
    assert_search 7, sexp,            s{ _ }
  end
end

class TestRemaining < MatcherTestCase
  def matcher
    s{ ___ }
  end

  def bad_sexp
    nil
  end

  def inspect_str
    "___"
  end

  def test_remaining_satisfy_eh # TODO: possibly remove
    assert_satisfy s{ ___         }, s(:a)
    assert_satisfy s{ ___         }, s(:a, :b, :c)
    assert_satisfy s{ s(:x, ___ ) }, s(:x, :y)
    refute_satisfy s{ s(:y, ___ ) }, s(:x, :y)
  end

  def test_greedy
    assert_operator matcher, :greedy?
  end
end

class TestAny < MatcherTestCase
  def matcher
    s{ s(:a) | s(:c) }
  end

  def inspect_str
    "q(:a) | q(:c)"
  end

  def pretty_str
    "any(q(:a), q(:c))"
  end

  def test_any_search # TODO: possibly remove
    assert_search 2, s(:foo, s(:a), s(:b)), s{ s(any(:a, :b)) }
    assert_search 1, s(:foo, s(:a), s(:b)), s{ any( s(:a), s(:c)) }
  end

  def test_or_satisfy_eh # TODO: possibly remove
    assert_satisfy s{ s(:a) | s(:b) }, s(:a)
    refute_satisfy s{ s(:a) | s(:b) }, s(:c)
  end

  def test_or_search # TODO: possibly remove
    sexp = CLASS_SEXP.dup

    assert_search 2, s(:a, s(:b, :c), s(:b, :d)), s{ s(:b, :c) | s(:b, :d) }
    assert_search 2, sexp, s{ s(:add, :a, :b) | s(:defn, :bar, _, _) }
  end
end

class TestAll < MatcherTestCase
  def matcher
    s{ s(:a) & s(:a) }
  end

  def inspect_str
    "q(:a) & q(:a)"
  end

  def pretty_str
    "all(q(:a), q(:a))"
  end

  def test_and_satisfy_eh # TODO: possibly remove
    refute_satisfy s{ s(:a) & s(:b)   }, s(:a)
    assert_satisfy s{ s(:a) & s(atom) }, s(:a)
  end
end

class TestNot < MatcherTestCase
  def matcher
    s{ not? s(:b) } # TODO: test unary minus
  end

  def inspect_str
    "not?(q(:b))" # TODO: change?
  end

  def pretty_str
    "not?(q(:b))" # TODO: change?
  end

  def test_not_satisfy_eh # TODO: possibly remove
    refute_satisfy s{ -_            }, s(:a)
    assert_satisfy s{ -s(:b)        }, s(:a)
    assert_satisfy s{ not?(s(:b)) }, s(:a)
    refute_satisfy s{ -s(atom)      }, s(:a)
    assert_satisfy s{ s(not?(:b)) }, s(:a)
  end
end

class TestChild < MatcherTestCase
  def matcher
    s{ child(s(:a)) }
  end

  def sexp
    s(:x, s(:a))
  end

  def bad_sexp
    s(:x, s(:b))
  end

  def inspect_str
    "child(q(:a))"
  end

  def test_child_search # TODO: possibly remove
    sexp = CLASS_SEXP.dup

    assert_search 1, sexp, s{ s(:class, :cake, _, _, child( s(:sub, :a, :b) ) ) }
    assert_search 1, sexp, s{ s(:class, :cake, _, _, child(include(:a))) }
  end

  def test_satisfy_eh_by_child
    assert_satisfy matcher, s(:a)
  end
end

class TestAtom < MatcherTestCase
  def matcher
    s{ atom }
  end

  def sexp
    42
  end

  def bad_sexp
    s(:a)
  end

  def inspect_str
    "atom"
  end

  def test_atom_satisfy_eh # TODO: possibly remove
    a = s{ atom }

    assert_satisfy a, :a
    assert_satisfy a, 1
    assert_satisfy a, nil
    refute_satisfy a, s()
  end

  def test_atom_search # TODO: possibly remove
    sexp = CLASS_SEXP.dup

    assert_search 1, s(:add, :a, :b), s{ s(:add, atom, :b) }
    assert_search 2, sexp,            s{ s(:defn, atom, _, s(atom, :a, :b) ) }
    assert_search 0, s(:a, s()),      s{ s(:a, atom) }
  end
end

class TestPattern < MatcherTestCase
  def matcher
    s{ s(:a, m(/a/)) }
  end

  def sexp
    s(:a, :blah)
  end

  def inspect_str
    "q(:a, m(/a/))"
  end

  def test_pattern_satisfy_eh # TODO: possibly remove
    assert_satisfy s{ m(/a/)     }, :a
    assert_satisfy s{ m(/^test/) }, :test_case
    assert_satisfy s{ m("test")  }, :test
    refute_satisfy s{ m("test")  }, :test_case
    refute_satisfy s{ m(/a/)     }, s(:a)
  end

  def test_pattern_search # TODO: possibly remove
    sexp = CLASS_SEXP.dup

    assert_search 2, sexp, s{ s(m(/\w{3}/), :a, :b) }
  end
end

class TestType < MatcherTestCase
  def matcher
    s{ t(:a) }
  end

  def test_type_satisfy_eh # TODO: possibly remove
    assert_satisfy s{ t(:a) }, s(:a)
    assert_satisfy s{ t(:a) }, s(:a, :b, s(:oh_hai), :d)
  end

  def test_type_search
    assert_search 2, CLASS_SEXP.dup, s{ t(:defn) }
  end

  def inspect_str
    "t(:a)"
  end
end

class TestInclude < MatcherTestCase
  def sexp
    s(:x, s(:a))
  end

  def matcher
    s{ include(s(:a)) }
  end

  def inspect_str
    "include(q(:a))"
  end

  def test_include_search # TODO: possibly remove
    sexp = CLASS_SEXP.dup

    assert_search 1, s(:add, :a, :b), s{ include(:a) }
    assert_search 1, sexp, s{ include(:bar) }
    assert_search 2, sexp, s{ s(:defn, atom, _, include(:a)) }
    assert_search 2, sexp, s{ include(:a) }
    assert_search 0, s(:a, s(:b, s(:c))), s{ s(:a, include(:c)) }
  end
end

class TestSibling < MatcherTestCase
  def sexp
    s(:x, s(:a), s(:x), s(:b))
  end

  def matcher
    s{ s(:a) >> s(:b) }
  end

  def inspect_str
    "q(:a) >> q(:b)"
  end

  def test_pretty_print_distance
    m = s{ M::Sibling.new(s(:a), s(:b), 3) } # maybe s(:a) << s(:b) << 3 ?
    assert_pretty_print "sibling(q(:a), q(:b), 3)", m
  end

  def test_sibling_satisfy_eh # TODO: possibly remove
    a_a = s{ s(:a) >> s(:a) }
    a_b = s{ s(:a) >> s(:b) }
    a_c = s{ s(:a) >> s(:c) }
    c_a = s{ s(:c) >> s(:a) }

    assert_satisfy a_b, s(s(:a), s(:b))
    assert_satisfy a_b, s(s(:a), s(:b), s(:c))
    assert_satisfy a_c, s(s(:a), s(:b), s(:c))
    refute_satisfy c_a, s(s(:a), s(:b), s(:c))
    refute_satisfy a_a, s(s(:a))
    assert_satisfy a_a, s(s(:a), s(:b), s(:a))
  end

  def test_sibling_search # TODO: possibly remove
    sexp = CLASS_SEXP.dup

    assert_search 1, sexp, s{ t(:defn) >> t(:defn) }
  end
end

class TestMatchResult < SexpTestCase
  attr_accessor :sexp, :pat, :act

  def setup
    self.sexp = s(:a, :b, :c)
    self.pat  = s{ _ }
    self.act  = (sexp / pat).first
  end

  def test_index
    self.act = (s(:a, :b, :c) / s{ _ }).first

    assert_equal sexp, act.sexp
  end

  def test_index_eq
    act[:key] = :val

    assert_equal :val, act[:key]
  end

  def test_to_s
    assert_equal "MatchResult.new(s(:a, :b, :c))", act.to_s
  end

  def test_to_s_capture
    act[:cheat] = :woot

    assert_equal "MatchResult.new(s(:a, :b, :c), {:cheat=>:woot})", act.to_s
  end

  def test_inspect
    assert_inspect "MatchResult.new(s(:a, :b, :c), {})", act
  end

  def test_pretty_print
    assert_pretty_print "MatchResult.new(s(:a, :b, :c), {})", act
  end

  def test_sanity
    exp = MR.new sexp

    assert_equal exp, act
  end
end

class TestMatchCollection < SexpTestCase
  attr_accessor :sexp, :pat, :act

  def setup
    self.sexp = s(:a, :b, :c)
    self.pat  = s{ _ }
    self.act  = sexp / pat
  end

  def test_slash
    self.sexp =
      s(:class, :cake, nil,
        s(:defn, :foo, s(:args), s(:add, :a, :b)),
        s(:defn, :bar, s(:args), s(:sub, :a, :b)))

    res = sexp / s{ s(:class, atom, _, ___) } # sexp / pat => MC
    act = res / s{ s(:defn, atom, ___) }      # MC   / pat => MC

    _, _, _, defn1, defn2 = sexp

    exp = MC.new
    exp << MR.new(defn1.deep_clone)
    exp << MR.new(defn2.deep_clone)

    assert_equal exp, act
  end

  def test_sanity
    act = sexp / pat
    exp = MC.new << MR.new(sexp)

    assert_equal exp, act
  end

  STR = "MatchCollection.new(MatchResult.new(s(:a, :b, :c), {}))"

  def test_to_s
    assert_equal STR, act.to_s
  end

  def test_inspect
    assert_inspect STR, act
  end

  def test_pretty_print
    assert_pretty_print STR, act
  end
end

class TestSexpSearch < SexpTestCase
  attr_accessor :sexp

  make_my_diffs_pretty!

  def setup
    self.sexp = CLASS_SEXP.dup
  end

  def coll *args
    exp = MC.new

    args.each_slice 2 do |sexp, hash|
      exp << res(sexp, hash)
    end

    exp
  end

  def res sexp, hash
    MR.new sexp.deep_clone, hash
  end

  def test_slash_simple
    act = sexp / s{ s(:class, atom, _, ___) }

    exp = MC.new
    exp << MR.new(sexp.deep_clone)

    assert_equal exp, act
  end

  def test_slash_subsexp
    act = sexp / s{ s(:defn, atom, ___) }

    exp = MC.new
    exp << MR.new(s(:defn, :foo, s(:args), s(:add, :a, :b)))
    exp << MR.new(s(:defn, :bar, s(:args), s(:sub, :a, :b)))

    assert_equal exp, act
  end

  def test_slash_data
    pat = s{ s(:defn, m(/^test_.+/), ___ ) }

    _, _, (_klass, _, _, _setup, t1, t2, t3) = TestUseCase.sexp.deep_clone
    exp = [t1, t2, t3]

    assert_equal exp, (TestUseCase.sexp.deep_clone / pat).map(&:sexp)
  end

  def test_search_each_no_block
    assert_kind_of Enumerator, sexp.search_each(s{_})
    assert_equal 7, sexp.search_each(s{_}).count
    assert_equal 2, sexp.search_each(s{t(:defn)}).count
    assert_search 7, sexp, s{_}
    assert_search 2, sexp, s{t(:defn)}

    _, _, _, defn1, defn2 = sexp

    mc = []
    mc << MR.new(defn1)
    mc << MR.new(defn2)

    assert_equal mc, sexp.search_each(s{t(:defn)}).map(&:itself)
  end

  def test_searching_simple_examples # TODO: possibly remove
    assert_raises ArgumentError do
      assert_search 0, sexp, :class # non-pattern should raise
    end

    assert_search 0, sexp,                s{ s(:class) }
    assert_search 1, sexp,                s{ s(:add, :a, :b) }
    assert_search 1, s(:a, s(:b, s(:c))), s{ s(:b, s(:c)) }
    assert_search 0, s(:a, s(:b, s(:c))), s{ s(:a, s(:c)) }
    assert_search 1, sexp,                s{ s(:defn, :bar, _, s(:sub, :a, :b)) }
  end

  def test_satisfy_eh_any_capture # TODO: remove
    sexp = s(:add, :a, :b)
    assert_satisfy s{ any(s(:add, :a, :b), s(:sub, :a, :b)) }, sexp

    assert_satisfy s{ any(s(atom, :a, :b), s(:sub, :a, :b)) }, sexp
  end

  def test_satisfy_eh_all_capture # TODO: remove
    sexp = s(:add, :a, :b)
    assert_satisfy s{ all(s(_, :a, :b), s(atom, :a, :b)) }, sexp

    assert_satisfy s{ all(s(_, :a, :b), s(atom, :a, :b)) }, sexp

    assert_search 1, sexp, s{ all(s(_, :a, :b), s(atom, :a, :b)) }
  end
end

class TestSexpPath < Minitest::Test
  def test_global_s_block
    sexp = s(:a, :b, :c) # s called outside block

    assert_instance_of Sexp,          s{ sexp.deep_clone }
    assert_instance_of Sexp::Matcher, s{ s(:a, :b, :c) }
    assert_instance_of Sexp::Matcher, s{ s(:a, atom, :c) }
  end
end

class TestSexpReplaceSexp < SexpTestCase
  def test_replace_sexp
    sexp = s(:a, s(:b), :c)
    actual = sexp.replace_sexp(s{ s(:b) }) { :b }

    assert_equal s(:a, :b, :c), actual
  end

  def test_replace_sexp_root
    sexp = s(:a, s(:b), :c)
    actual = sexp.replace_sexp(s{ t(:a) }) { s(:new) }

    assert_equal s(:new), actual
  end

  def test_replace_sexp_yields_match_result
    sexp = s(:a, s(:b), :c)

    exp = M::MatchResult.new(sexp)

    sexp.replace_sexp(s{ t(:a) }) { |x|
      assert_equal exp, x
    }
  end

  def test_replace_sexp_non_matcher
    e = assert_raises ArgumentError do
      s(:a, s(:b), :c).replace_sexp(42) { :b }
    end

    assert_equal "Needs a pattern", e.message
  end

  def test_search_each_yields_match_result
    sexp = s(:a, s(:b), :c)

    exp = M::MatchResult.new(sexp)

    sexp.search_each(s{ t(:a) }) { |x|
      assert_equal exp, x
    }
  end

  def test_search_each_no_pattern
    e = assert_raises ArgumentError do
      s(:a, s(:b), :c).search_each(42) { :b }
    end

    assert_equal "Needs a pattern", e.message
  end
end

# Here's a crazy idea, these tests actually use sexp_path on some "real"
# code to see if it can satisfy my requirements.
#
# These tests are two fold:
# 1. Make sure it works
# 2. Make sure it's not painful to use

class TestUseCase < SexpTestCase
  @@sexp = eval File.read(__FILE__).split(/^__END__/).last

  def self.sexp
    @@sexp
  end

  def setup
    @sexp = @@sexp.deep_clone
  end

  def test_finding_methods
    methods = @sexp / s{ t(:defn) }
    assert_equal 5, methods.length
  end

  def test_finding_classes_and_methods
    res = @sexp / s{ s(:class, atom, ___ ) }

    _klass, name, * = res.first.sexp

    assert_equal 1, res.length
    assert_equal :ExampleTest, name

    methods = res / s{ t(:defn) }
    assert_equal 5, methods.length
  end

  def test_finding_empty_test_methods
    empty_test = s{ s(:defn, m(/^test_.+/), s(:args), s(:nil)) }
    res = @sexp / empty_test

    _, _, (_klass, _, _, _setup, _t1, t2, _t3) = TestUseCase.sexp.deep_clone

    assert_equal [t2], res.map(&:sexp)
  end

  def test_search_each_finding_duplicate_test_names
    pat = s{ s(:defn, m(/^test_.+/), ___ ) }
    counts = Hash.new { |h, k| h[k] = 0 }

    @sexp.search_each pat do |x|
      _, name, * = x.sexp
      counts[name] += 1
    end

    assert_equal 1, counts[:test_b], "Should have seen test_b once"
    assert_equal 2, counts[:test_a], "Should have caught test_a being repeated"
  end

  def test_finding_duplicate_test_names_via_res
    pat = s{ s(:defn, m(/^test_.+/), ___ ) }
    res = @sexp / pat
    counts = Hash.new { |h, k| h[k] = 0 }

    _, _, (_klass, _, _, _setup, t1, t2, t3) = TestUseCase.sexp.deep_clone
    exp = [t1, t2, t3]

    assert_equal exp, res.map(&:sexp)

    res.each do |m|
      _, name, *_ = m.sexp
      counts[name] += 1
    end

    assert_equal 1, counts[:test_b], "Should have seen test_b once"
    assert_equal 2, counts[:test_a], "Should have caught test_a being repeated"
  end

  def test_rewriting_colon2s
    colon2   = s{ s(:colon2, s(:const, atom), atom) }
    expected = s{ s(:const, "Minitest::Test") }

    new_sexp = @sexp.replace_sexp(colon2) { |r|
      (_, (_, a), b) = r.sexp
      s(:const, "%s::%s" % [a, b])
    }

    assert_search 1, new_sexp, expected
    assert_search 0, @sexp, expected
  end
end

##
# NOTE: this entire class is now redundant, but it illustrates usage
#       and edge cases well.

class TestSexpMatchers < SexpTestCase
  CLASS_LIT = s(:class, :X, nil,
                s(:lasgn, :x, s(:lit, 42)),
                s(:cdecl, :Y,
                  s(:hash, s(:lit, :a), s(:lit, 1), s(:lit, :b), s(:lit, 2))))

  SEXP = s(:class, :X, nil, s(:defn, :x, s(:args)))

  def test_match_subset
    assert_match s{ child(s(:a)) }, s(:blah, s(:blah, s(:a)))
    assert_match s{ child(s(:a)) }, s(:a)
  end

  def test_match_simple
    assert_match s{ s(:lit, _) }, s(:lit, 42)
  end

  def test_match_mismatch_type
    refute_match s{ s(:xxx, 42) }, s(:lit, 42)
  end

  def test_match_mismatch_data
    refute_match s{ s(:lit, 24) }, s(:lit, 42)
  end

  def test_match_mismatch_length_shorter
    refute_match s{ s(:a, :b) }, s(:a, :b, :c)
  end

  def test_match_mismatch_length_longer
    refute_match s{ s(:a, :b, :c) }, s(:a, :b)
  end

  def test_match_wild
    assert_match s{ s(:class, _, _, _) }, SEXP
  end

  def test_match_rest_same_length
    assert_match s{ s(:class, _, _, ___) }, SEXP
  end

  def test_match_rest_diff_length
    skip_if_strict

    assert_match s{ s(:class, ___) }, SEXP
  end

  def test_match_reversed
    assert_match SEXP, s{ s(:class, _, _, ___) }
  end

  def assert_match_case pat, data
    case data
    when pat then
      assert true
    else
      flunk "Expected %p to match %p" % [pat, data]
    end
  end

  def test_match_case
    assert_match_case s{ s(:class, _, _, ___) }, SEXP
  end

  # NOTE: eqt is =~ (equal-tilde)

  # cmt = create_match_test
  def self.cmt e1, e2, e3, e4, lit, pat
    Class.new SexpTestCase do
      attr_accessor :lit, :pat

      define_method :setup do
        self.lit = lit
        self.pat = pat
      end

      define_method :test_match_lit_eqt_pat do
        skip_if_strict

        if e1 then
          assert_match lit, pat
        else
          refute_match lit, pat
        end
      end

      define_method :test_match_pat_eqt_lit do
        skip_if_strict

        if e2 then
          assert_match pat, lit
        else
          refute_match pat, lit
        end
      end

      define_method :test_match_lit_eq3_pat do
        if e3 then
          assert_equal3 lit, pat
        else
          refute_equal3 lit, pat
        end
      end

      define_method :test_match_pat_eq3_lit do
        if e4 then
          assert_equal3 pat, lit
        else
          refute_equal3 pat, lit
        end
      end
    end
  end

  l_a   = s(:a)
  l_abc = s(:a, s(:b, s(:c)))
  l_cls = s(:class, :X, nil,
            s(:something_in_between),
            s(:cdecl, :Y, s(:hash, s(:lit, :a), s(:lit, 1))))
  p_cls1 = s{ s(:class, ___) & include(s(:cdecl, _, s(:hash, ___))) }
  p_cls2 = s{ s(:class, _, _, s(:cdecl, _, s(:hash, ___))) }

  x, o = true, false
  TestMatcherDirectMatch       = cmt x, x, o, x, l_a,   s{ s(:a) }
  TestMatcherSubtree           = cmt x, x, o, x, l_abc, s{ s(:c) }
  TestMatcherSubtreeType       = cmt x, x, o, x, l_abc, s{ t(:c) }
  TestMatcherDisparateSubtree  = cmt x, x, o, x, l_cls, p_cls1
  TestMatcherDisparateSubtree2 = cmt o, o, o, o, l_cls, p_cls2 # TODO: make pass
end

class TestSexpMatcherParser < Minitest::Test
  def assert_parse exp, str
    act = Sexp::Matcher.parse str

    if exp.nil? then
      assert_nil act
    else
      assert_equal exp, act
    end
  end

  def self.test_parse name, exp_lambda, str
    define_method "test_parse_#{name}" do
      exp = exp_lambda && exp_lambda.call
      assert_parse exp, str
    end
  end

  def self.test_bad_parse name, str
    define_method "test_parse_bad_#{name}" do
      assert_raises SyntaxError do
        assert_parse :whatever, str
      end
    end
  end

  def self.delay &b
    lambda { s(&b) }
  end

  test_parse "nothing",  nil,                             ""
  test_parse "nil",      delay{ nil },                        "nil"
  test_parse "empty",    delay{ s() },                        "()"
  test_parse "simple",   delay{ s(:a) },                      "(a)"
  test_parse "number",   delay{ s(:a, 42) },                  "(a 42)"
  test_parse "string",   delay{ s(:a, "s") },                 "(a \"s\")"
  test_parse "compound", delay{ s(:b) },                      "(a) (b)"
  test_parse "complex",  delay{ s(:a, _, s(:b, :cde), ___) }, "(a _ (b cde) ___)"
  test_parse "type",     delay{ s(:a, t(:b)) },               "(a [t b])"
  test_parse "match",    delay{ s(:a, m(/b/)) },              "(a [m /b/])"
  test_parse "not_atom", delay{ s(:atom) },                   "(atom)"
  test_parse "atom",     delay{ atom },                       "[atom]"

  test_bad_parse "open_sexp",   "(a"
  test_bad_parse "closed_sexp", "a)"
  test_bad_parse "open_cmd",    "[a"
  test_bad_parse "closed_cmd",  "a]"
end # class TestSexpMatcherParser

class BenchSexp < Minitest::Benchmark
  def run
    GC.disable
    super
  ensure
    GC.enable
  end

  def self.bench_range
    bench_linear 100, 500, 50
  end

  @@data = Hash[bench_range.map { |n| [n, pyramid_sexp(n)] }]

  def bench_pyramid
    assert_performance_power do |max|
      pyramid_sexp max
    end
  end

  def bench_mass
    assert_performance_power do |max|
      @@data[max].mass
    end
  end
end if ENV["BENCH"]

# class ExampleTest < Minitest::Test
#   def setup
#     1 + 2
#   end
#
#   def test_a
#     assert_equal 1+2, 4
#   end
#
#   def test_b
#     # assert 1+1
#   end
#
#   def test_a
#     assert_equal 1+2, 3
#   end
#
#   private
#
#   def helper_method apples, oranges, cakes = nil
#     [apples, oranges, cakes].compact.map { |food| food.to_s.upcase }
#   end
# end

__END__
s(:block,
 s(:call, nil, :require, s(:str, "minitest/autorun")),
 s(:class,
  :ExampleTest,
  s(:colon2, s(:const, :Minitest), :Test),
  s(:defn, :setup, s(:args), s(:call, s(:lit, 1), :+, s(:lit, 2))),
  s(:defn,
   :test_a,
   s(:args),
   s(:call,
    nil,
    :assert_equal,
    s(:call, s(:lit, 1), :+, s(:lit, 2)),
    s(:lit, 4))),
  s(:defn, :test_b, s(:args), s(:nil)),
  s(:defn,
   :test_a,
   s(:args),
   s(:call,
    nil,
    :assert_equal,
    s(:call, s(:lit, 1), :+, s(:lit, 2)),
    s(:lit, 3))),
  s(:call, nil, :private),
  s(:defn,
   :helper_method,
   s(:args, :apples, :oranges, s(:lasgn, :cakes, s(:nil))),
   s(:iter,
    s(:call,
     s(:call,
      s(:array, s(:lvar, :apples), s(:lvar, :oranges), s(:lvar, :cakes)),
      :compact),
     :map),
    s(:args, :food),
    s(:call, s(:call, s(:lvar, :food), :to_s), :upcase)))))
