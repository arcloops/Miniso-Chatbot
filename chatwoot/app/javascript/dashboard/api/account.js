/* global axios */
import ApiClient from './ApiClient';

class AccountAPI extends ApiClient {
  constructor() {
    super('', { accountScoped: true });
  }

  get(accountId) {
    return accountId
      ? axios.get(`${this.apiVersion}/accounts/${accountId}`)
      : super.get();
  }

  createAccount(data) {
    return axios.post(`${this.apiVersion}/accounts`, data);
  }

  async getCacheKeys() {
    const response = await axios.get(
      `/api/v1/accounts/${this.accountIdFromRoute}/cache_keys`
    );
    return response.data.cache_keys;
  }

  getProductSheets() {
    return axios.get(`${this.url}product_sheets`);
  }

  getProductSheet(id) {
    return axios.get(`${this.url}product_sheets/${id}`);
  }

  uploadProductSheet(file) {
    const form = new FormData();
    form.append('file', file);
    return axios.post(`${this.url}product_sheets`, form);
  }

  deleteProductSheet(id) {
    return axios.delete(`${this.url}product_sheets/${id}`);
  }
}

export default new AccountAPI();
