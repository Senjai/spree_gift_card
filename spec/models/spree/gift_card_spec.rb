require 'spec_helper'

describe Spree::GiftCard do
  it {should have_many(:transactions)}

  it {should validate_presence_of(:current_value)}
  it {should validate_numericality_of(:current_value).is_greater_than_or_equal_to(0)}
  it {should validate_presence_of(:email)}
  it {should validate_presence_of(:original_value)}
  it {should validate_numericality_of(:original_value).is_greater_than_or_equal_to(0)}
  it {should validate_presence_of(:name)}

  context "when expiration_date isn't set" do
    it "should set expiration to default" do
      Timecop.freeze
      card = Spree::GiftCard.create(email: "test@mail.com", name: "John", variant_id: create(:variant).id)
      expect(card.expiration_date).to eq(Spree::GiftCard.default_expiration_date)
      Timecop.return
    end
  end

  context "when expiration_date is set" do
    it "should leave expiration_date" do
      Timecop.freeze
      card = Spree::GiftCard.create(email: "test@mail.com", name: "John", variant_id: create(:variant).id, expiration_date: 2.days.from_now)
      expect(card.expiration_date).to eq(2.days.from_now)
      Timecop.return
    end
  end

  it "should generate code before create" do
    card = Spree::GiftCard.create(:email => "test@mail.com", :name => "John", :variant_id => create(:variant).id)
    card.code.should_not be_nil
  end

  it "should set current_value and original_value before create" do
    card = Spree::GiftCard.create(:email => "test@mail.com", :name => "John", :variant_id => create(:variant).id)
    card.current_value.should_not be_nil
    card.original_value.should_not be_nil
  end

  it "does not set current and original values if there is no variant" do
    card = Spree::GiftCard.create(:email => "test@mail.com", :name => "John")

    card.current_value.should be_nil
    card.original_value.should be_nil
    card.valid?.should be_false
  end

  describe "soft deleting the card" do
    let!(:card) { create :gift_card }
    let!(:calculator_id) { card.calculator.id }
    before do
      card.destroy
    end

    context "deleting the card" do
      it "is not shown without the with deleted scope" do
        expect(described_class.all).to be_empty
      end

      it "is shown with the with_deleted scope" do
        expect(described_class.with_deleted).to include(card)
      end

      it "retains its calculator on soft delete" do
        expect(described_class.with_deleted.first.calculator.id).to eql(calculator_id)
      end
    end

    context "restoring the card", focus: true do
      before do
        card.restore
      end

      it "is restored" do
        expect(card.deleted_at).to be_nil
      end

      it "keeps its original calculator when it's restored" do
        expect(card.reload.calculator.id).to eql(calculator_id)
      end
    end
  end

  describe ".active" do
    let!(:card) { create :gift_card, expiration_date: expiration_date }

    subject { described_class.all.active }

    before do
      allow(DateTime).to receive(:current).and_return("2014-04-29T20:53:56+00:00".to_datetime)
    end

    context "with an inactive card" do
      let(:expiration_date) { "2014-04-28 23:59:59 UTC".to_datetime }

      it "isn't active" do
        expect(subject).to_not include(card)
      end
    end

    context "with an active card" do
      let(:expiration_date) { "2014-04-29T23:59:59+00:00".to_datetime }

      it "is active" do
        expect(subject).to include(card)
      end
    end

    context "with a card that should be active but isn't" do
      let(:expiration_date) { "2014-04-29T20:48:56+00:00".to_datetime }

      it "isn't active" do
        expect(subject).to_not include(card)
      end
    end
  end

  describe '.expired?' do
    let(:gift_card) { create(:gift_card) }

    subject { gift_card.expired?}
    context "when expiration_date is in the future" do
      before do
        allow(gift_card).to receive(:expiration_date).and_return(5.days.from_now)
      end

      specify{ expect(subject).to be_false}

    end

    context "when expiration_date is in the past" do
      before do
        allow(gift_card).to receive(:expiration_date).and_return(5.days.ago)
      end

      specify { expect(subject).to be_true }
    end
  end

  context ".sortable_attributes" do
    subject { described_class.sortable_attributes }

    it { should have(6).items }
    it { should include(["Creation Date", "created_at"]) }
    it { should include(["Expiration Date", "expiration_date"]) }
    it { should include(["Redemption Code", "code"]) }
    it { should include(["Current Balance", "current_value"]) }
    it { should include(["Original Balance", "original_value"]) }
    it { should include(["Note", "note"]) }
  end

  context '#activatable?' do
    let(:gift_card) { create(:gift_card, variant: create(:variant, price: 25)) }
    let(:user) { create(:user) }

    context "when the gift card has no user" do
      it 'should not be activatable if no current value' do
        gift_card.stub :current_value => 0
        gift_card.order_activatable?(mock_model(Spree::Order, state: 'cart', user: user)).should be_false
      end

      it 'should not be activatable if expired' do
        gift_card.stub expired?: true
        gift_card.order_activatable?(mock_model(Spree::Order, state: 'cart', user: user)).should be_false
      end


      it 'should not be activatable if invalid order state' do
        gift_card.order_activatable?(mock_model(Spree::Order, state: 'complete', user: user)).should be_false
      end
    end

    context "when the gift card has a user" do
      let(:order) { build_stubbed(:order, user: order_user) }
      before do
        gift_card.update_column(:user_id, user.id)
      end

      subject { gift_card.order_activatable?(order) }

      context "when the user on the order matches the user on the gift card" do
        let(:order_user) { user }

        it { should be_true }
      end
      context "when the user on the order does not match the user on the gift card" do
        let(:order_user) { create(:user) }

        it { should be_false }
      end
    end
  end

  describe '#apply' do
    let(:gift_card) { create(:gift_card, variant: create(:variant, price: 25)) }
    subject { gift_card.apply(order) }

    it 'creates adjustment with mandatory set to true' do
      order = create(:order_with_totals)
      create(:line_item, order: order, price: 75, variant: create(:variant, price: 75))
      order.reload # reload so line item is associated
      order.update!
      gift_card.apply(order)
      order.adjustments.find_by_originator_id_and_originator_type(gift_card.id, gift_card.class.to_s).mandatory.should be_true
    end

    context "when gift card is expired" do
      let(:order) { create(:order_with_totals) }

      before do
        allow(gift_card).to receive(:expired?).and_return(true)
      end

      it "raises an expired gift card exception" do
        expect{subject}.to raise_error(Spree::GiftCard::ExpiredGiftCardException)
      end
    end

    context "when gift card is not expired" do
      let(:order) { create(:order_with_totals) }

      before do
        allow(gift_card).to receive(:expired?).and_return(false)
      end

      it "returns true" do
        gift_card.apply(order).should be_true
      end
    end

    context 'for order total larger than gift card amount' do
      it 'creates adjustment for full amount' do
        order = create(:order_with_totals)
        create(:line_item, order: order, price: 75, variant: create(:variant, price: 75))
        order.reload # reload so line item is associated
        order.update!
        gift_card.apply(order)
        order.adjustments.find_by_originator_id_and_originator_type(gift_card.id, gift_card.class.to_s).amount.to_f.should eql(-25.0)
      end
    end

    context "when the order has a user" do
      let!(:order) { create :order }

      context "when the gift card has a user" do
        let!(:gift_card) { create :gift_card, user: user }

        context "when the gift cards user equals the orders user" do
          let(:user) { order.user }

          it { should be_true }
        end

        context "when the gift cards user does not equal the orders user" do
          let(:user) { create :user }

          it "raises an invalid user exception" do
            expect{subject}.to raise_error(Spree::GiftCard::InvalidUserException)
          end
        end
      end

      context "when the gift card does not have a user" do
        let!(:gift_card) { create :gift_card, user: nil }

        it { should be_true }

        it "associates the gift card with the orders user" do
          subject
          expect(gift_card.user).to eql(order.user)
        end
      end
    end

    context "when the order doesn't have a user" do
      let!(:order) { create :order, user: nil, email: "1234@hello.ca" }

      context "when the gift card has a user" do
        let!(:gift_card) { create :gift_card, user: create(:user) }

        it "raises an invalid user exception" do
          expect{subject}.to raise_error(Spree::GiftCard::InvalidUserException)
        end
      end

      context "when the gift card has no user" do
        let!(:gift_card) { create :gift_card, user: nil }

        it { should be_true }
      end
    end

    context 'for order total smaller than gift card amount' do
      it 'creates adjustment for order total' do
        order = create(:order_with_totals)
        order.reload # reload so line item is associated
        order.update! # update so order calculates totals
        gift_card.apply(order)
        # default line item is priced at 10
        order.adjustments.find_by_originator_id_and_originator_type(gift_card.id, gift_card.class.to_s).amount.to_f.should eql(-10.0)
      end
    end
  end

  context '#debit' do
    let(:gift_card) { create(:gift_card, variant: create(:variant, price: 25)) }
    let(:order) { create(:order) }

    it 'should raise an error when attempting to debit an amount higher than the current value' do
      lambda {
        gift_card.debit(-30, order)
      }.should raise_error
    end

    it 'should subtract used amount from the current value and create a transaction' do
      gift_card.debit(-25, order)
      gift_card.reload # reload to ensure accuracy
      gift_card.current_value.to_f.should eql(0.0)
      transaction = gift_card.transactions.first
      transaction.amount.to_f.should eql(-25.0)
      transaction.gift_card.should eql(gift_card)
      transaction.order.should eql(order)
    end
  end

  describe "#price" do
    let!(:li) { create(:line_item, price: 5, quantity: 5) }
    let!(:variant) { create(:variant) }

    let(:gc1) { create(:gift_card, line_item: li) }
    let(:gc2) { create(:gift_card, line_item: nil, variant: variant) }
    let(:gc3) { create(:gift_card, line_item: nil, variant: nil, original_value: 8, current_value: 8) }

    subject { gift_card.price }

    context "when the gift card has a line_item" do
      let(:gift_card) { gc1 }

      it { should eql(li.price * li.quantity) }
    end

    context "when the gift card has no line_item but has a variant" do
      let(:gift_card) { gc2 }

      it { should eql(variant.price) }
    end

    context "when the gift card has no line_item or variant but has a current_value" do
      let(:gift_card) { gc3 }

      it { should eql(gc3.current_value) }
    end
  end

  describe "#active" do
    subject { Spree::GiftCard.active }

    let!(:expired_gc) { create :expired_gc }
    let!(:redeemed_gc) { create :redeemed_gc }
    let!(:gift_card) { create :gift_card }

    it { should include gift_card }
    it { should_not include redeemed_gc }
    it { should_not include expired_gc }
  end

  describe ".status" do
    subject { gift_card.status }
    let(:gift_card) { create :gift_card }

    it { should eq :active }

    context "when it's balance is zero" do
      before { gift_card.current_value = 0.0 }
      it { should eq :redeemed }
    end

    context "when it's past the expiration date" do
      before { gift_card.expiration_date = Time.current - 1.day }
      it { should eq :expired }
    end
  end
end
