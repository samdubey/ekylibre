# == License
# Ekylibre - Simple agricultural ERP
# Copyright (C) 2008-2011 Brice Texier, Thibaud Merigon
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

module Backend
  class ParcelsController < Backend::BaseController
    manage_restfully t3e: { nature: 'RECORD.nature.text'.c }, planned_at: 'Time.zone.now'.c
    manage_restfully_attachments

    respond_to :csv, :ods, :xlsx, :pdf, :odt, :docx, :html, :xml, :json

    unroll

    # params:
    #   :q Text search
    #   :s State search
    #   :period Two Dates with _ separator
    #   :recipient_id
    #   :sender_id
    #   :transporter_id
    #   :delivery_mode Choice
    #   :nature Choice
    def self.parcels_conditions
      code = ''
      code = search_conditions(parcels: [:number, :reference_number], entities: [:full_name, :number]) + " ||= []\n"
      code << "unless params[:period].blank? || params[:period].is_a?(Symbol)\n"
      code << "  if params[:period] != 'all'\n"
      code << "    interval = params[:period].split('_')\n"
      code << "    first_date = interval.first\n"
      code << "    last_date = interval.last\n"
      code << "    c[0] << \" AND #{Parcel.table_name}.planned_at BETWEEN ? AND ?\"\n"
      code << "    c << first_date\n"
      code << "    c << last_date\n"
      code << "  end\n "
      code << "end\n "
      code << "if params[:recipient_id].to_i > 0\n"
      code << "  c[0] << \" AND \#{Parcel.table_name}.recipient_id = ?\"\n"
      code << "  c << params[:recipient_id].to_i\n"
      code << "end\n"
      code << "if params[:sender_id].to_i > 0\n"
      code << "  c[0] << \" AND \#{Parcel.table_name}.sender_id = ?\"\n"
      code << "  c << params[:sender_id].to_i\n"
      code << "end\n"
      code << "if params[:transporter_id].to_i > 0\n"
      code << "  c[0] << \" AND \#{Parcel.table_name}.transporter_id = ?\"\n"
      code << "  c << params[:transporter_id].to_i\n"
      code << "end\n"
      code << "if params[:delivery_mode].present? && params[:delivery_mode] != 'all'\n"
      code << "  if Parcel.delivery_mode.values.include?(params[:delivery_mode].to_sym)\n"
      code << "    c[0] << ' AND #{Parcel.table_name}.delivery_mode = ?'\n"
      code << "    c << params[:delivery_mode]\n"
      code << "  end\n"
      code << "end\n"
      code << "if params[:nature].present? && params[:nature] != 'all'\n"
      code << "  if Parcel.nature.values.include?(params[:nature].to_sym)\n"
      code << "    c[0] << ' AND #{Parcel.table_name}.nature = ?'\n"
      code << "    c << params[:nature]\n"
      code << "  end\n"
      code << "end\n"
      code << "c\n"
      code.c
    end

    list(conditions: parcels_conditions, order: { planned_at: :desc }) do |t|
      t.action :new,     on: :none
      t.action :invoice, on: :both, method: :post, if: :invoiceable?
      t.action :ship,    on: :both, method: :post, if: :shippable?
      t.action :edit
      t.action :destroy
      t.column :number, url: true
      t.column :reference_number, hidden: true
      t.column :nature
      t.column :planned_at
      t.column :recipient, url: true
      t.column :sender, url: true
      t.status
      t.column :human_state_name
      t.column :delivery, url: true
      t.column :transporter, url: true, hidden: true
      # t.column :sent_at
      t.column :delivery_mode
      # t.column :net_mass, hidden: true
      t.column :sale, url: true
      t.column :purchase, url: true
    end

    list(:items, model: :parcel_items, conditions: { parcel_id: 'params[:id]'.c }) do |t|
      t.column :product, url: true
      # t.column :product_work_number, through: :product, label_method: :work_number
      t.column :population
      t.column :unit_name, through: :variant
      t.column :variant, url: true
      t.status
      # t.column :net_mass
      t.column :analysis, url: true
      t.column :source_product, url: true, hidden: true
    end

    # Displays the main page with the list of parcels
    def index
      respond_to do |format|
        format.html
        format.xml { render xml: @parcels }
        format.pdf { render pdf: @parcels, with: params[:template] }
      end
    end

    # Displays details of one parcel selected with +params[:id]+
    def show
      return unless @parcel = find_and_check
      respond_with(@parcel, methods: [:all_item_prepared, :status, :items_quantity],
                            include: { address: { methods: [:mail_coordinate] },
                                       sale: {},
                                       purchase: {},
                                       recipient: {},
                                       sender: {},
                                       transporter: {},
                                       items: { methods: [:status, :prepared], include: [:product, :variant] }
                            }
                  ) do |format|
        format.html do
          t3e @parcel.attributes.merge(nature: @parcel.nature.text)
        end
      end
    end

    # Converts parcel to trade
    def invoice
      parcels = find_parcels
      return unless parcels
      parcel = parcels.first
      if parcels.all? { |p| p.incoming? && p.third_id == parcel.third_id && p.invoiceable? }
        purchase = Parcel.convert_to_purchase(parcels)
        redirect_to backend_purchase_url(purchase)
      elsif parcels.all? { |p| p.outgoing? && p.third_id == parcel.third_id && p.invoiceable? }
        sale = Parcel.convert_to_sale(parcels)
        redirect_to backend_sale_url(sale)
      else
        notify_error(:all_parcels_must_be_invoiceable_and_of_same_nature_and_third)
        redirect_to(params[:redirect] || { action: :index })
      end
    end

    # Pre-fill delivery form with given parcels. Nothing else.
    # Only a shortcut now.
    def ship
      parcels = find_parcels
      return unless parcels
      parcel = parcels.detect { |p| p.shippable? && !p.delivery_mode_indifferent? }
      options = { parcel_ids: parcels.map(&:id) }
      if !parcel
        redirect_to(options.merge(controller: :deliveries, action: :new))
      elsif parcels.all? { |p| p.shippable? && (p.delivery_mode_indifferent? || p.delivery_mode == parcel.delivery_mode) }
        options[:mode] = parcel.delivery_mode
        options[:transporter_id] = parcel.transporter_id if parcel.transporter
        redirect_to(options.merge(controller: :deliveries, action: :new))
      else
        notify_error(:some_parcels_are_not_shippable)
        redirect_to(params[:redirect] || { action: :index })
      end
    end

    Parcel.state_machine.events.each do |event|
      define_method event.name do
        fire_event(event.name)
      end
    end

    protected

    def find_parcels
      parcel_ids = params[:id].split(',')
      parcels = parcel_ids.map { |id| Parcel.find_by(id: id) }.compact
      unless parcels.any?
        notify_error :no_parcels_given
        redirect_to(params[:redirect] || { action: :index })
        return nil
      end
      parcels
    end
  end
end
