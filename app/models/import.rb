# = Informations
#
# == License
#
# Ekylibre - Simple agricultural ERP
# Copyright (C) 2008-2009 Brice Texier, Thibaud Merigon
# Copyright (C) 2010-2012 Brice Texier
# Copyright (C) 2012-2014 Brice Texier, David Joulin
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see http://www.gnu.org/licenses.
#
# == Table: imports
#
#  archive_content_type   :string(255)
#  archive_file_name      :string(255)
#  archive_file_size      :integer
#  archive_updated_at     :datetime
#  created_at             :datetime         not null
#  creator_id             :integer
#  id                     :integer          not null, primary key
#  imported_at            :datetime
#  importer_id            :integer
#  lock_version           :integer          default(0), not null
#  nature                 :string(255)      not null
#  progression_percentage :decimal(19, 4)
#  state                  :string(255)      not null
#  updated_at             :datetime         not null
#  updater_id             :integer
#
class Import < Ekylibre::Record::Base
  belongs_to :importer, class_name: "User"
  enumerize :nature, in: Nomen::ExchangeNatures.all
  enumerize :state, in: [:undone, :in_progress, :errored, :aborted, :finished], predicates: true, default: :undone
  has_attached_file :archive, path: ':tenant/:class/:id/:style.:extension'
  #[VALIDATORS[ Do not edit these lines directly. Use `rake clean:validations`.
  validates_numericality_of :archive_file_size, allow_nil: true, only_integer: true
  validates_numericality_of :progression_percentage, allow_nil: true
  validates_length_of :archive_content_type, :archive_file_name, :nature, :state, allow_nil: true, maximum: 255
  validates_presence_of :nature, :state
  #]VALIDATORS]
  validates_inclusion_of :progression_percentage, in: 0..100, allow_blank: true
  do_not_validate_attachment_file_type :archive


  # Run an import.
  # The optional code block permit have access to progression on each check point
  def run(&block)
    self.update_columns(state: :in_progress, progression_percentage: 0)
    Ekylibre::Record::Base.transaction do
      Exchanges.import(self.nature, self.archive) do |importer|
        self.update_column(progression_percentage: importer.progression)
        yield importer if block_given?
      end
      self.update_column(state: :finished, progression_percentage: 100)
    end
    if self.in_progress?
      self.update_column(state: :errored, progression_percentage: 0)
    end
  end

end