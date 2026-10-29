<script>
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useConfig } from 'dashboard/composables/useConfig';
import { useAccount } from 'dashboard/composables/useAccount';
import { FEATURE_FLAGS } from '../../../../featureFlags';
import WithLabel from 'v3/components/Form/WithLabel.vue';
import NextInput from 'next/input/Input.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import AccountId from './components/AccountId.vue';
import BuildInfo from './components/BuildInfo.vue';
import AccountDelete from './components/AccountDelete.vue';
import AudioTranscription from './components/AudioTranscription.vue';
import SectionLayout from './components/SectionLayout.vue';
import AccountAPI from 'dashboard/api/account';

export default {
  components: {
    BaseSettingsHeader,
    NextButton,
    AccountId,
    BuildInfo,
    AccountDelete,
    AudioTranscription,
    SectionLayout,
    WithLabel,
    NextInput,
  },
  setup() {
    const { updateUISettings, uiSettings } = useUISettings();
    const { enabledLanguages } = useConfig();
    const { accountId } = useAccount();
    const v$ = useVuelidate();

    return { updateUISettings, uiSettings, v$, enabledLanguages, accountId };
  },
  data() {
    return {
      id: '',
      name: '',
      locale: 'en',
      domain: '',
      supportEmail: '',
      website: '',
      botDescription: '',
      features: {},
      productSheet: null,
      productSheets: [],
      openSheet: null,
      sheetFile: null,
      isUploadingSheet: false,
      sheetPoll: null,
      sheetPolls: 0,
    };
  },
  validations: {
    name: {
      required,
    },
    locale: {
      required,
    },
  },
  computed: {
    ...mapGetters({
      getAccount: 'accounts/getAccount',
      uiFlags: 'accounts/getUIFlags',
      isFeatureEnabledonAccount: 'accounts/isFeatureEnabledonAccount',
      isOnChatwootCloud: 'globalConfig/isOnChatwootCloud',
    }),
    showAudioTranscriptionConfig() {
      return this.isFeatureEnabledonAccount(
        this.accountId,
        FEATURE_FLAGS.CAPTAIN
      );
    },
    languagesSortedByCode() {
      const enabledLanguages = [...this.enabledLanguages];
      return enabledLanguages.sort((l1, l2) =>
        l1.iso_639_1_code.localeCompare(l2.iso_639_1_code)
      );
    },
    isUpdating() {
      return this.uiFlags.isUpdating;
    },
    featureInboundEmailEnabled() {
      return !!this.features?.inbound_emails;
    },
    featureCustomReplyDomainEnabled() {
      return (
        this.featureInboundEmailEnabled && !!this.features.custom_reply_domain
      );
    },
    featureCustomReplyEmailEnabled() {
      return (
        this.featureInboundEmailEnabled && !!this.features.custom_reply_email
      );
    },
    currentAccount() {
      return this.getAccount(this.accountId) || {};
    },
  },
  watch: {
    'currentAccount.id'(id) {
      if (id) {
        this.initializeAccount();
      }
    },
  },
  mounted() {
    // Account already in the store (navigated in): seed immediately.
    if (this.currentAccount.id) {
      this.initializeAccount();
    }
  },
  beforeUnmount() {
    this.stopSheetPoll();
  },
  methods: {
    async initializeAccount() {
      try {
        const {
          name,
          locale,
          id,
          domain,
          support_email,
          features,
          custom_attributes: customAttributes = {},
        } = this.getAccount(this.accountId);

        const effectiveLocale = this.uiSettings?.locale || locale;
        if (effectiveLocale) {
          this.$root.$i18n.locale = effectiveLocale;
        }
        this.name = name;
        this.locale = locale;
        this.id = id;
        this.domain = domain;
        this.supportEmail = support_email;
        this.website = customAttributes.website || '';
        this.botDescription = customAttributes.bot_description || '';
        this.features = features;
        this.productSheet = this.getAccount(this.accountId).product_sheet || null;
        this.loadProductSheets();
      } catch (error) {
        // Ignore error
      }
    },

    onSheetSelected(event) {
      const [file] = event.target.files || [];
      this.sheetFile = file || null;
    },

    async loadProductSheets() {
      try {
        const { data } = await AccountAPI.getProductSheets();
        this.productSheets = data;
        this.productSheet = data[0] || null;
        if (
          this.openSheet &&
          !data.some(sheet => sheet.id === this.openSheet.id)
        ) {
          this.openSheet = null;
        }
        this.scheduleSheetPoll();
      } catch (error) {
        // The list appears after the first upload.
      }
    },

    scheduleSheetPoll() {
      this.stopSheetPoll();
      const pending = this.productSheets.some(
        sheet =>
          sheet.image_status === 'pending' || sheet.image_status === 'processing'
      );
      if (!pending || this.sheetPolls > 20) return;

      this.sheetPolls += 1;
      this.sheetPoll = setTimeout(async () => {
        await this.loadProductSheets();
      }, 5000);
    },

    stopSheetPoll() {
      if (!this.sheetPoll) return;
      clearTimeout(this.sheetPoll);
      this.sheetPoll = null;
    },

    imageStatusText(sheet) {
      if (!sheet || !sheet.image_status || sheet.image_status === 'none') return '';
      if (sheet.image_status === 'pending' || sheet.image_status === 'processing') {
        return this.$t('GENERAL_SETTINGS.FORM.PRODUCT_SHEET.IMAGES_PENDING');
      }
      const stats = sheet.image_stats || {};
      if (!stats.discovered) return '';
      return this.$t('GENERAL_SETTINGS.FORM.PRODUCT_SHEET.IMAGES', {
        indexed: stats.indexed || 0,
        reused: stats.reused || 0,
        failed: stats.failed || 0,
      });
    },

    async viewProductSheet(sheet) {
      if (this.openSheet && this.openSheet.id === sheet.id) {
        this.openSheet = null;
        return;
      }
      try {
        const { data } = await AccountAPI.getProductSheet(sheet.id);
        this.openSheet = data;
      } catch (error) {
        useAlert(this.$t('GENERAL_SETTINGS.FORM.PRODUCT_SHEET.ERROR'));
      }
    },

    async uploadProductSheet() {
      if (!this.sheetFile) return;
      this.isUploadingSheet = true;
      try {
        await AccountAPI.uploadProductSheet(this.sheetFile);
        await this.$store.dispatch('accounts/get');
        this.sheetFile = null;
        if (this.$refs.sheetInput) this.$refs.sheetInput.value = '';
        this.sheetPolls = 0;
        await this.loadProductSheets();
        useAlert(this.$t('GENERAL_SETTINGS.FORM.PRODUCT_SHEET.SUCCESS'));
      } catch (error) {
        useAlert(
          error?.response?.data?.error ||
            this.$t('GENERAL_SETTINGS.FORM.PRODUCT_SHEET.ERROR')
        );
      } finally {
        this.isUploadingSheet = false;
      }
    },

    async removeProductSheet(sheet) {
      this.isUploadingSheet = true;
      try {
        await AccountAPI.deleteProductSheet(sheet.id);
        await this.$store.dispatch('accounts/get');
        await this.loadProductSheets();
        useAlert(this.$t('GENERAL_SETTINGS.FORM.PRODUCT_SHEET.REMOVE_SUCCESS'));
      } catch (error) {
        useAlert(this.$t('GENERAL_SETTINGS.FORM.PRODUCT_SHEET.ERROR'));
      } finally {
        this.isUploadingSheet = false;
      }
    },

    async updateAccount() {
      this.v$.$touch();
      if (this.v$.$invalid) {
        useAlert(this.$t('GENERAL_SETTINGS.FORM.ERROR'));
        return;
      }
      try {
        await this.$store.dispatch('accounts/update', {
          locale: this.locale,
          name: this.name,
          domain: this.domain,
          support_email: this.supportEmail,
          website: this.website,
          bot_description: this.botDescription,
        });
        // If user locale is set, update the locale with user locale
        const updatedLocale = this.uiSettings?.locale || this.locale;
        if (updatedLocale) {
          this.$root.$i18n.locale = updatedLocale;
        }
        this.getAccount(this.id).locale = this.locale;
        useAlert(this.$t('GENERAL_SETTINGS.UPDATE.SUCCESS'));
      } catch (error) {
        useAlert(this.$t('GENERAL_SETTINGS.UPDATE.ERROR'));
      }
    },
  },
};
</script>

<template>
  <div class="flex flex-col w-full max-w-2xl ltr:mr-auto rtl:ml-auto">
    <BaseSettingsHeader :title="$t('GENERAL_SETTINGS.TITLE')" />
    <div class="flex-grow flex-shrink min-w-0 mt-3">
      <SectionLayout
        :title="$t('GENERAL_SETTINGS.FORM.GENERAL_SECTION.TITLE')"
        :description="$t('GENERAL_SETTINGS.FORM.GENERAL_SECTION.NOTE')"
        class="!pt-0"
      >
        <form
          v-if="!uiFlags.isFetchingItem"
          class="grid gap-4"
          @submit.prevent="updateAccount"
        >
          <WithLabel
            name="account-name"
            :has-error="v$.name.$error"
            :label="$t('GENERAL_SETTINGS.FORM.NAME.LABEL')"
            :error-message="$t('GENERAL_SETTINGS.FORM.NAME.ERROR')"
          >
            <NextInput
              v-model="name"
              type="text"
              class="w-full"
              :placeholder="$t('GENERAL_SETTINGS.FORM.NAME.PLACEHOLDER')"
              @blur="v$.name.$touch"
            />
          </WithLabel>
          <WithLabel
            name="site-language"
            :has-error="v$.locale.$error"
            :label="$t('GENERAL_SETTINGS.FORM.LANGUAGE.LABEL')"
            :error-message="$t('GENERAL_SETTINGS.FORM.LANGUAGE.ERROR')"
          >
            <select v-model="locale" class="!mb-0 text-sm">
              <option
                v-for="lang in languagesSortedByCode"
                :key="lang.iso_639_1_code"
                :value="lang.iso_639_1_code"
              >
                {{ lang.name }}
              </option>
            </select>
          </WithLabel>
          <WithLabel
            name="company-website"
            :label="$t('GENERAL_SETTINGS.FORM.WEBSITE.LABEL')"
          >
            <NextInput
              v-model="website"
              type="text"
              class="w-full"
              :placeholder="$t('GENERAL_SETTINGS.FORM.WEBSITE.PLACEHOLDER')"
            />
            <template #help>
              {{ $t('GENERAL_SETTINGS.FORM.WEBSITE.HELP') }}
            </template>
          </WithLabel>
          <WithLabel
            name="company-description"
            :label="$t('GENERAL_SETTINGS.FORM.BOT_DESCRIPTION.LABEL')"
          >
            <textarea
              v-model="botDescription"
              rows="5"
              class="w-full"
              :placeholder="
                $t('GENERAL_SETTINGS.FORM.BOT_DESCRIPTION.PLACEHOLDER')
              "
            />
            <template #help>
              {{ $t('GENERAL_SETTINGS.FORM.BOT_DESCRIPTION.HELP') }}
            </template>
          </WithLabel>
          <WithLabel
            v-if="featureCustomReplyDomainEnabled"
            name="custom-domain"
            :label="$t('GENERAL_SETTINGS.FORM.DOMAIN.LABEL')"
          >
            <NextInput
              v-model="domain"
              type="text"
              class="w-full"
              :placeholder="$t('GENERAL_SETTINGS.FORM.DOMAIN.PLACEHOLDER')"
            />
            <template #help>
              {{
                featureInboundEmailEnabled &&
                $t('GENERAL_SETTINGS.FORM.FEATURES.INBOUND_EMAIL_ENABLED')
              }}

              {{
                featureCustomReplyDomainEnabled &&
                $t('GENERAL_SETTINGS.FORM.FEATURES.CUSTOM_EMAIL_DOMAIN_ENABLED')
              }}
            </template>
          </WithLabel>
          <WithLabel
            v-if="featureCustomReplyEmailEnabled"
            name="support-email"
            :label="$t('GENERAL_SETTINGS.FORM.SUPPORT_EMAIL.LABEL')"
          >
            <NextInput
              v-model="supportEmail"
              type="text"
              class="w-full"
              :placeholder="
                $t('GENERAL_SETTINGS.FORM.SUPPORT_EMAIL.PLACEHOLDER')
              "
            />
          </WithLabel>
          <div>
            <NextButton blue :is-loading="isUpdating" type="submit">
              {{ $t('GENERAL_SETTINGS.SUBMIT') }}
            </NextButton>
          </div>
        </form>
      </SectionLayout>

      <SectionLayout
        :title="$t('GENERAL_SETTINGS.FORM.PRODUCT_SHEET.TITLE')"
        :description="$t('GENERAL_SETTINGS.FORM.PRODUCT_SHEET.NOTE')"
        with-border
      >
        <div class="grid gap-3">
          <input
            ref="sheetInput"
            type="file"
            accept=".csv,.xlsx,text/csv"
            class="text-sm"
            @change="onSheetSelected"
          />
          <div class="flex gap-2">
            <NextButton
              blue
              type="button"
              :is-loading="isUploadingSheet"
              :disabled="!sheetFile"
              @click="uploadProductSheet"
            >
              {{ $t('GENERAL_SETTINGS.FORM.PRODUCT_SHEET.BUTTON') }}
            </NextButton>
          </div>
          <div v-if="productSheets.length" class="grid gap-2">
            <h5 class="mb-0 text-sm font-medium text-n-slate-12">
              {{ $t('GENERAL_SETTINGS.FORM.PRODUCT_SHEET.HISTORY') }}
            </h5>
            <div
              v-for="sheet in productSheets"
              :key="sheet.id"
              class="grid gap-2 rounded-lg border border-n-weak p-3"
            >
              <div class="flex flex-wrap items-center justify-between gap-2">
                <div>
                  <p class="mb-0 text-sm text-n-slate-12">
                    {{
                      $t('GENERAL_SETTINGS.FORM.PRODUCT_SHEET.STATUS', {
                        filename: sheet.filename,
                        count: sheet.row_count,
                        date: sheet.updated_at,
                      })
                    }}
                  </p>
                  <p v-if="sheet.current" class="mb-0 text-xs text-n-slate-11">
                    {{ $t('GENERAL_SETTINGS.FORM.PRODUCT_SHEET.CURRENT') }}
                  </p>
                  <p v-if="imageStatusText(sheet)" class="mb-0 text-xs text-n-slate-11">
                    {{ imageStatusText(sheet) }}
                  </p>
                </div>
                <div class="flex gap-2">
                  <NextButton
                    type="button"
                    faded
                    slate
                    sm
                    @click="viewProductSheet(sheet)"
                  >
                    {{
                      openSheet && openSheet.id === sheet.id
                        ? $t('GENERAL_SETTINGS.FORM.PRODUCT_SHEET.HIDE')
                        : $t('GENERAL_SETTINGS.FORM.PRODUCT_SHEET.VIEW')
                    }}
                  </NextButton>
                  <NextButton
                    type="button"
                    faded
                    ruby
                    sm
                    :disabled="isUploadingSheet"
                    @click="removeProductSheet(sheet)"
                  >
                    {{ $t('GENERAL_SETTINGS.FORM.PRODUCT_SHEET.REMOVE') }}
                  </NextButton>
                </div>
              </div>
              <div
                v-if="openSheet && openSheet.id === sheet.id"
                class="overflow-auto max-h-80"
              >
                <p
                  v-if="openSheet.rows && openSheet.rows.length > 200"
                  class="mb-2 text-xs text-n-slate-11"
                >
                  {{
                    $t('GENERAL_SETTINGS.FORM.PRODUCT_SHEET.SHOWING', {
                      shown: 200,
                      count: openSheet.row_count,
                    })
                  }}
                </p>
                <table class="w-full text-sm text-left">
                  <thead>
                    <tr>
                      <th
                        v-for="(header, headerIndex) in openSheet.headers"
                        :key="headerIndex"
                        class="px-2 py-1 font-medium"
                      >
                        {{ header }}
                      </th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr
                      v-for="(row, rowIndex) in openSheet.rows.slice(0, 200)"
                      :key="rowIndex"
                    >
                      <td
                        v-for="(cell, cellIndex) in row"
                        :key="cellIndex"
                        class="px-2 py-1 border-t border-n-weak"
                      >
                        {{ cell }}
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        </div>
      </SectionLayout>

      <woot-loading-state v-if="uiFlags.isFetchingItem" />
    </div>
    <AudioTranscription v-if="showAudioTranscriptionConfig" />
    <AccountId />
    <div v-if="!uiFlags.isFetchingItem && isOnChatwootCloud">
      <AccountDelete />
    </div>
    <BuildInfo />
  </div>
</template>
