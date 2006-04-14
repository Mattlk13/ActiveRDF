# = query_engine.rb
#
# Engine to generate query for different adapter (Yars, SPARQL).
#
# == Project
#
# * ActiveRDF
# <http://m3pe.org/activerdf/>
#
# == Authors
# 
# * Eyal Oren <first dot last at deri dot org>
# * Renaud Delbru <first dot last at deri dot org>
#
# == Copyright
#
# (c) 2005-2006 by Eyal Oren and Renaud Delbru - All Rights Reserved
#

require 'node_factory'

class QueryEngine

	# Arguments
	attr_reader :related_resource
	private :related_resource

	# Container Attributes
	attr_reader :bindings, :binding_triple, :conditions, :order, :distinct
	private :bindings, :binding_triple, :conditions, :order, :distinct

	# Initialize the query engine.
	#
	# Arguments:
	# * +connection+ [<tt>AbstractAdapter</tt>]: The connection used to execute query.
	# * +related_resource+ [<tt>Resource</tt>]: Resource related to the query
	def initialize(related_resource = nil)
		@count = NodeFactory.create_basic_resource 'http://sw.deri.org/2004/06/yars#count'
		@related_resource = related_resource

		@bindings = nil
		@binding_triple = nil
		@conditions = nil
		@order = nil
		@distinct = nil
		@count_variables = false
	end
  
#----------------------------------------------#
#               PRIVATE METHODS                #
#----------------------------------------------#

	private

	# Clean all containers (bindings, conditions, order)
	def clean
		@bindings = nil
		@binding_triple = nil
		@conditions = nil
		@order = nil
		@distinct = nil
		@count_variables = false
	end
  
	# Convert predicate if a resource is related to the query, e.g. verify if predicate is
	# included in the resource attributes (for :title, look for a 'title' attribute),
	# and convert it into a Resource.
	#
	# Arguments:
	# * +predicate+: Symbol representing the predicate.
	#
	# Return:
	# * Return a Resource if the predicate is included, a Symbol otherwise.
	def convert_predicate(predicate)
		predicates = @related_resource.predicates	

		if predicate.is_a?(Symbol) && predicates.key?(predicate.to_s)
			predicate = predicates[predicate.to_s]
		end

		return predicate
	end

#----------------------------------------------#
#               PUBLIC METHODS                 #
#----------------------------------------------#

	public

	# Add bindings variables in the select clause to the query (for Sparql)
	#
	# Arguments:
	# * +args+ [<tt>Array</tt>]: Array of Symbol. Each symbol is a binding variable.
	def add_binding_variables(*args)
		if @bindings.nil?
			@bindings = args
		else
			@bindings += args
		end
	end

	def add_counting_variable(arg)
		raise(QueryError,'cannot count more than one variable') if arg.kind_of? Array
		raise(QueryError, 'can only count unbound variables') unless arg.kind_of? Symbol
		@count_variables = true

		# TODO: Commented since YARS counting is broken
		## add binding variable to the select list
		##add_select_variables :n
		##add_condition arg, @count, :n
		
		# TODO: now adding arg itself to select, and then counting uniq results 
		# (change it back later to use yars:count)
		add_binding_variables arg
	end


	# Add a binding triple in the select clause to the query (for Yars). Only one
	# triple is allowed for the moment.
	#
	# Arguments:
	# * +subject+ : Subject of the triple (Symbol or Resource)
	# * +predicate+ : Predicate of the triple (Symbol or Resource)
	# * +object+ : Object of the triple (Symbol, Resource, String, ...)
	def add_binding_triple(subject, predicate, object)
		@binding_triple = [[subject, predicate, object]]
	end

	# Add a condition in the where clause. Convert the predicate if a resource is
	# related to the query.
	#
	# Arguments:
	# * +subject+ : Subject of the triple (Symbol or Resource)
	# * +predicate+ : Predicate of the triple (Symbol or Resource)
	# * +object+ : Object of the triple (Symbol, Resource, String, ...)
	def add_condition(subject, predicate, object)
		$logger.debug "adding condition: #{subject} #{predicate} #{object}"
		@conditions = Array.new if @conditions.nil?
		if @related_resource.nil?
			@conditions << [subject, predicate, object]
		else
			@conditions << [subject, convert_predicate(predicate), object]
		end
		$logger.debug "added condition: #{subject} #{predicate} #{object}"
	end

	# Add an order option on a binding variable
	#
	# Arguments:
	# * +binding_variable+ : binding variable (Symbol) to order
	# * +descendant+ : Boolean which True if we want a descendant order.
	def order_by(binding_variable, descendant=true)
		@order = Hash.new if @order.nil?
		@order[binding_variable] = descendant
	end

	# Activate the keyword searching on Literal object
	def activate_keyword_search
		@keyword_search = true
	end

	# Generate a Sparql query. Return the query string.
	# Take only the array of binding variables.
	def generate_sparql
		raise(BindingVariableError, "In #{__FILE__}:#{__LINE__}, SPARQL doesn't support binding triple.") if @binding_triple
		raise(WrongTypeQueryError, "In #{__FILE__}:#{__LINE__}, SPARQL doesn't support counting triples.") if @count_variables

		require 'query_generator/sparql_generator.rb'
		return SparqlQueryGenerator.generate(@bindings, @conditions, @order, @keyword_search)
	end

	# Generate a NTriples query. Return the query string.
	# Can take the array of binding variable or a binding triple.
	def generate_ntriples	
		if (@bindings and @binding_triple)
			raise(BindingVariableError, "In #{__FILE__}:#{__LINE__}, cannot add a binding triple with binding variables.")
		end
	
		require 'query_generator/ntriples_generator.rb'
		return NTriplesQueryGenerator.generate(@bindings, @conditions, @order, @keyword_search) if @bindings
		return NTriplesQueryGenerator.generate(@binding_triple, @conditions, @order, @keyword_search) if @binding_triple
	end

	# Choose the query language and generate the query string.
	def generate
		case NodeFactory.connection.query_language
		when 'sparql'
			return generate_sparql
		when 'n3'
			return generate_ntriples
		else
			raise(LanguageUnknownQueryError, "In #{__FILE__}:#{__LINE__}, Unknown query language.")
		end
	end

	# Execute the query on a database, depending of the connection, and after clean
	# all the containers (bindings, conditions, order).
	#
	# Return:
	# * [<tt>Array</tt>] Array containing the results of the query, nil if no result.
	def execute
		# Choose the query language and generate the query string
		qs = generate
		counting = @count_variables

		# Clean containers
		clean

		# Execute query
		results = NodeFactory.connection.query(qs)
		if counting
			# TODO: commented because yars:count broken, change back later
##			counts = results.collect{|result| result.value.to_i}
##			return counts[0] if counts.size == 1
##			return counts
			#
			return results.uniq.size
		else
			results
		end
	end

end
