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
      sheetFile: null,
      isUploadingSheet: false,
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
      } catch (error) {
        // Ignore error
      }
    },

    onSheetSelected(event) {
      const [file] = event.target.files || [];
      this.sheetFile = file || null;
    },

    async uploadProductSheet() {
      if (!this.sheetFile) return;
      this.isUploadingSheet = true;
      try {
        await AccountAPI.uploadProductSheet(this.sheetFile);
        await this.$store.dispatch('accounts/get');
        this.sheetFile = null;
        if (this.$refs.sheetInput) this.$refs.sheetInput.value = '';
        this.initializeAccount();
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

    async removeProductSheet() {
      this.isUploadingSheet = true;
      try {
        await AccountAPI.deleteProductSheet();
        await this.$store.dispatch('accounts/get');
        this.initializeAccount();
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
          <p v-if="productSheet" class="mb-0 text-sm text-n-slate-12">
            {{
              $t('GENERAL_SETTINGS.FORM.PRODUCT_SHEET.STATUS', {
                filename: productSheet.filename,
                count: productSheet.row_count,
                date: productSheet.updated_at,
              })
            }}
          </p>
          <p
            v-if="productSheet && productSheet.truncated"
            class="mb-0 text-sm text-n-slate-11"
          >
            {{
              $t('GENERAL_SETTINGS.FORM.PRODUCT_SHEET.TRUNCATED', {
                count: productSheet.row_count,
              })
            }}
          </p>
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
            <NextButton
              v-if="productSheet"
              type="button"
              faded
              slate
              :disabled="isUploadingSheet"
              @click="removeProductSheet"
            >
              {{ $t('GENERAL_SETTINGS.FORM.PRODUCT_SHEET.REMOVE') }}
            </NextButton>
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
