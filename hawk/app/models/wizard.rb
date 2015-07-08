# Copyright (c) 2009-2015 Tim Serong <tserong@suse.com>
# Copyright (c) 2015 Kristoffer Gronlund <kgronlund@suse.com>
# See COPYING for license information.

class Wizard < Tableless
  attribute :name, String
  attribute :category, String
  attribute :shortdesc, String
  attribute :longdesc, String

  attribute :loaded, Boolean
  attribute :steps, StepCollection[Step]

  def load!
    return if @loaded
    CrmScript.run ["show", @name] do |item, err|
      Rails.logger.error "Wizard.load!: #{err}" unless err.nil?
      self.load_from item unless item.nil?
    end
  end

  def load_from(data)
    # TODO: load steps data
    data['steps'].each do |step|
      @steps.build step
    end
    @loaded = true
  end

  def steps
    @steps ||= StepCollection.new
  end

  def flattened_steps
    ret = []
    @steps.each do |step|
      ret << step unless step.parameters.empty?
      ret.concat step.flattened_steps
    end
    ret
  end

  def valid?
    super & steps.valid?
  end

  def verify(params)
    # TODO: Check loaded
    CrmScript.run ["verify", @name, params] do |item, err|
      Rails.logger.debug "#{item}, #{err}"
    end
  end

  def run(params)
    # TODO: Check loaded
    # TODO: live-update frontend
    CrmScript.run ["run", @name, params] do |item, err|
      Rails.logger.debug "#{item}, #{err}"
    end
  end

  class << self
    def parse_brief(data)
      return Wizard.new(
               name: data['name'],
               category: data['category'].strip.downcase,
               shortdesc: data['shortdesc'].strip,
               longdesc: data['longdesc'].gsub(/\n/, '<br>'),
               loaded: false
             )
    end

    def parse_full(data)
      wizard = Wizard.new(
        name: data['name'],
        category: data['category'].strip.downcase,
        shortdesc: data['shortdesc'].strip,
        longdesc: data['longdesc'].gsub(/\n/, '<br>'),
        loaded: false
      )
      wizard.load_from data
      wizard
    end

    def find(name)
      wizard = Wizard.all.select{|w| w.name == name}.first
      raise CibObject::RecordNotFound, _("Requested wizard does not exist") if wizard.nil?
      wizard.load!
      wizard
    end

    def exclude_wizard(item)
      workflows = {'60-nfsserver' => true,
                   'mariadb' => true,
                   'ocfs2-single' => true,
                   'webserver' => true}
      unsupported = {'gfs2' => true,
                     'gfs2-base' => true}
      return true if item['category'].strip.downcase.eql? "script"
      return true if item['category'].strip.downcase.eql?("wizard") && workflows.has_key?(item['name'])
      return unsupported.has_key?(item['name'])
    end

    def all
      # TODO; Make the wizards cache expire after
      # a certain time (5 minutes or so?)
      @@wizards ||= []
      return @@wizards unless @@wizards.empty?
      CrmScript.run ["list"] do |item, err|
        Rails.logger.debug "Wizard.all: #{err}" unless err.nil?
        @@wizards << Wizard.parse_brief(item) unless item.nil? or self.exclude_wizard(item)
      end
      @@wizards
    end
  end
end
