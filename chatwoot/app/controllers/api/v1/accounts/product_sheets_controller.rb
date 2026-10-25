class Api::V1::Accounts::ProductSheetsController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?

  def create
    sheet = Accounts::ProductSheetService.new(Current.account).replace(params[:file])
    render json: sheet_payload(sheet)
  rescue Accounts::SpreadsheetReader::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    Accounts::ProductSheetService.new(Current.account).clear
    head :ok
  end

  private

  def sheet_payload(sheet)
    {
      filename: sheet.filename,
      row_count: sheet.row_count,
      updated_at: sheet.updated_at,
      truncated: sheet.truncated
    }
  end
end
