class Api::V1::Accounts::ProductSheetsController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?
  before_action :set_sheet, only: [:show, :destroy]

  def index
    sheets = Current.account.product_sheets.newest_first.limit(60).select(
      :id, :filename, :row_count, :truncated, :created_at, :image_status, :image_stats
    )
    current_id = sheets.first&.id
    render json: sheets.map { |sheet| sheet_summary(sheet, current_id) }
  end

  def show
    render json: sheet_summary(@sheet).merge(
      headers: @sheet.headers,
      rows: @sheet.rows
    )
  end

  def create
    sheet = Accounts::ProductSheetService.new(Current.account).replace(params[:file])
    render json: sheet_summary(sheet, sheet.id)
  rescue Accounts::SpreadsheetReader::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    Accounts::ProductSheetService.new(Current.account).clear(@sheet.id)
    head :ok
  end

  private

  def set_sheet
    @sheet = Current.account.product_sheets.find(params[:id])
  end

  def sheet_summary(sheet, current_id = nil)
    current_id = Current.account.product_sheets.newest_first.pick(:id) if current_id.nil?
    {
      id: sheet.id,
      filename: sheet.filename,
      row_count: sheet.row_count,
      updated_at: sheet.created_at,
      truncated: sheet.truncated,
      current: sheet.id == current_id,
      image_status: sheet.image_status,
      image_stats: sheet.image_stats || {}
    }
  end
end
