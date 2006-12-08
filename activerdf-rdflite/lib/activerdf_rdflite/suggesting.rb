require 'pp'
class SuggestingAdapter < FetchingAdapter
  ConnectionPool.register_adapter(:suggesting,self)

	alias _old_initialize initialize
	
	def initialize params
		_old_initialize(params)
		@db.execute('drop view if exists occurrence')
		@db.execute('create view occurrence as select p, count(distinct s) as count from triple group by p')

		@db.execute('drop view if exists cooccurrence')
		@db.execute('create view cooccurrence as select t0.p as p1,t1.p as p2, count(distinct t0.s) as count from triple as t0 join triple as t1 on t0.s=t1.s and t0.p!=t1.p group by t0.p, t1.p')
	end

	def suggest(resource)
		$activerdflog.debug "starting suggestions for #{size} triples"
		time = Time.now

    predicates = []
		own_predicates = resource.direct_predicates

		construct_occurrence_matrix
		construct_cooccurrence_matrix

		own_predicates.each do |p|
			predicates << p if occurrence(p) > 1
		end

		# fetch all predicates co-occurring with our predicates
		candidates = predicates.collect {|p| cooccurring(p) }

		# perform set intersection
		candidates = candidates.inject {|intersect, n| intersect & n }.flatten
		candidates = candidates - own_predicates

		suggestions = candidates.collect do |candidate|
			score = predicates.inject(1.0) do |score, p|
				score * cooccurrence(candidate, p) / occurrence(p)
			end
			[candidate, score]
		end
		$activerdflog.debug "suggestions for #{resource} took #{Time.now-time}s"
		suggestions
	end

	def construct_occurrence_matrix
		@occurrence = {}
		@db.execute('select * from occurrence where count > 1') do |p,count|
			@occurrence[parse(p)] = count.to_i
		end
	end

	def construct_cooccurrence_matrix
		@cooccurrence = {}
		@db.execute('select * from cooccurrence') do |p1, p2, count|
			@cooccurrence[parse(p1)] ||= {}
			@cooccurrence[parse(p1)][parse(p2)] = count.to_i
		end
	end

	def occurrence(predicate)
		@occurrence[predicate] || 0
	end

	def cooccurrence(p1, p2)
		@cooccurrence[p1][p2] || 0
	end

	def cooccurring(predicate)
		@cooccurrence[predicate].keys
	end
end