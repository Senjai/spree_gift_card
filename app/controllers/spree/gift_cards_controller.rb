module Spree
  class GiftCardsController < Spree::StoreController
    before_filter :find_gift_card, only: [:update, :transfer]

    def new
      find_gift_card_variants
      @gift_card = GiftCard.new
    end

    def index
      @show_all = params[:show_all] == "true"
      @gift_cards = current_spree_user.gift_cards.page(params[:page]).
        order(:expiration_date).reverse_order
      @gift_cards = @gift_cards.active unless @show_all

      @gift_cards.sort! do |a, b|
        comp = gc_sort_order[a.status] <=> gc_sort_order[b.status]
        comp.zero?? (b.expiration_date <=> a.expiration_date) : comp
      end
    end

    def transfer
    end

    def update
      if @gift_card.update_attributes transfer_params
        flash[:success] = Spree.t(:successfully_transferred_gift_card,
                                  email: transfer_params[:email])

        Spree::GiftCardMailer.gift_card_transferred(@gift_card,
                                                    current_spree_user.email).deliver

        redirect_to gift_cards_path
      else
        render action: :transfer
      end
    end

    def create
      begin
        # Wrap the transaction script in a transaction so it is an atomic operation
        Spree::GiftCard.transaction do
          @gift_card = GiftCard.new(gift_card_params)
          @gift_card.save!
          # Create line item
          line_item = LineItem.new(quantity: 1)
          line_item.gift_card = @gift_card
          line_item.variant = @gift_card.variant
          line_item.price = @gift_card.variant.price
          # Add to order
          order = current_order(create_order_if_necessary: true)
          order.line_items << line_item
          line_item.order=order
          order.save!
          # Save gift card
          @gift_card.line_item = line_item
          @gift_card.save!
        end
        redirect_to cart_path
      rescue ActiveRecord::RecordInvalid
        find_gift_card_variants
        render :action => :new
      end
    end

    private
    def find_gift_card_variants
      gift_card_product_ids = Product.not_deleted.where(is_gift_card: true).pluck(:id)
      @gift_card_variants = Variant.joins(:prices).where(["amount > 0 AND product_id IN (?)", gift_card_product_ids]).order("amount")
    end

    def transfer_params
      t_params = params.require(:gift_card).permit(:note, :email)
      set_user_in_params t_params
      t_params
    end

    def set_user_in_params params_hash
      if email = params_hash[:email]
        user = Spree::User.where(email: email).first
        params_hash[:user_id] = user ? user.id : nil
      end
    end

    def gift_card_params
      params.require(:gift_card).permit(:email, :name, :note, :variant_id)
    end

    def gc_sort_order
      {
        active: 1,
        redeemed: 2,
        expired: 3
      }
    end

    def find_gift_card
      @gift_card = current_spree_user.gift_cards.where(id: params[:id]).first
    end
  end
end
