Spree::CheckoutController.class_eval do
  append_before_filter :add_gift_codes, only: :update

  private

  def add_gift_codes
    if params[:gift_code]
      @order.gift_code = Array.wrap(params[:gift_code]).first
      unless apply_gift_codes
        flash[:error] = Spree.t(:gc_apply_failure)
        render :edit
        return
      end
    end
  end
end
