<script setup>
import { computed, reactive, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { required, email } from '@vuelidate/validators';
import { useVuelidate } from '@vuelidate/core';
import { splitName } from '@chatwoot/utils';
import countries from 'shared/constants/countries.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { useAccount } from 'dashboard/composables/useAccount';
import Input from 'dashboard/components-next/input/Input.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import CompanySelector from 'dashboard/components-next/Companies/CompanySelector.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import PhoneNumberInput from 'dashboard/components-next/phonenumberinput/PhoneNumberInput.vue';
import { socialProfileUrl } from 'dashboard/components-next/social-profiles/socialProfiles';
import { INBOX_TYPES } from 'dashboard/helper/inbox';

const props = defineProps({
  contactData: {
    type: Object,
    default: null,
  },
  isDetailsView: {
    type: Boolean,
    default: false,
  },
  isNewContact: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['update']);

const { t } = useI18n();
const { currentAccount, isCloudFeatureEnabled } = useAccount();

const FORM_CONFIG = {
  FIRST_NAME: { field: 'firstName' },
  LAST_NAME: { field: 'lastName' },
  EMAIL_ADDRESS: { field: 'email' },
  PHONE_NUMBER: { field: 'phoneNumber' },
  CITY: { field: 'additionalAttributes.city' },
  COUNTRY: { field: 'additionalAttributes.countryCode' },
  BIO: { field: 'additionalAttributes.description' },
  COMPANY_NAME: { field: 'additionalAttributes.companyName' },
};

const SOCIAL_CONFIG = {
  LINKEDIN: 'i-ri-linkedin-box-fill',
  FACEBOOK: 'i-ri-facebook-circle-fill',
  INSTAGRAM: 'i-ri-instagram-line',
  WHATSAPP: 'i-ri-whatsapp-line',
  TELEGRAM: 'i-ri-telegram-fill',
  TIKTOK: 'i-ri-tiktok-fill',
  TWITTER: 'i-ri-twitter-x-fill',
  GITHUB: 'i-ri-github-fill',
};

const defaultState = {
  id: 0,
  name: '',
  email: '',
  companyId: '',
  firstName: '',
  lastName: '',
  phoneNumber: '',
  additionalAttributes: {
    description: '',
    companyName: '',
    countryCode: '',
    country: '',
    city: '',
    socialProfiles: {
      facebook: '',
      github: '',
      instagram: '',
      telegram: '',
      tiktok: '',
      linkedin: '',
      twitter: '',
      whatsapp: '',
    },
  },
};

const state = reactive({ ...defaultState });

const validationRules = {
  firstName: { required },
  email: { email },
};

const v$ = useVuelidate(validationRules, state);

const isFormInvalid = computed(() => v$.value.$invalid);
const normalizeWhatsAppUsername = value => value?.toString().replace(/^@+/, '');
const hasCompaniesFeature = computed(
  () =>
    currentAccount.value?.id && isCloudFeatureEnabled(FEATURE_FLAGS.COMPANIES)
);

const emitContactUpdate = async () => {
  const isFormValid = await v$.value.$validate();
  if (!isFormValid) return;

  const { firstName, lastName, ...stateWithoutNames } = state;
  emit('update', stateWithoutNames);
};

const prepareStateBasedOnProps = () => {
  if (props.isNewContact) {
    return; // Added to prevent state update for new contact form
  }

  const {
    id,
    name = '',
    email: emailAddress,
    phoneNumber,
    companyId = '',
    additionalAttributes = {},
  } = props.contactData || {};
  const { firstName, lastName } = splitName(name || '');
  const {
    description = '',
    companyName = '',
    countryCode = '',
    country = '',
    city = '',
    socialTelegramUserName = '',
    socialWhatsappUserName = '',
    socialInstagramUserName = '',
    socialProfiles = {},
  } = additionalAttributes || {};

  const telegramUsername =
    socialProfiles?.telegram || socialTelegramUserName || '';
  const whatsappUsername = normalizeWhatsAppUsername(
    socialProfiles?.whatsapp || socialWhatsappUserName || ''
  );
  const instagramUsername = (
    socialProfiles?.instagram ||
    socialInstagramUserName ||
    ''
  )
    .toString()
    .replace(/^@+/, '');

  Object.assign(state, {
    id,
    name,
    companyId: companyId || '',
    firstName,
    lastName,
    email: emailAddress,
    phoneNumber,
    additionalAttributes: {
      description,
      companyName,
      countryCode,
      country,
      city,
      socialProfiles: {
        ...socialProfiles,
        instagram: instagramUsername,
        telegram: telegramUsername,
        whatsapp: whatsappUsername,
      },
    },
  });
};

const countryOptions = computed(() =>
  countries.map(({ name, id }) => ({ label: name, value: id }))
);

const editDetailsForm = computed(() =>
  Object.keys(FORM_CONFIG).map(key => ({
    key,
    placeholder: t(
      `CONTACTS_LAYOUT.CARD.EDIT_DETAILS_FORM.FORM.${key}.PLACEHOLDER`
    ),
  }))
);

const CHANNEL_LABELS = {
  [INBOX_TYPES.FB]: 'Messenger',
  [INBOX_TYPES.INSTAGRAM]: 'Instagram',
  [INBOX_TYPES.WHATSAPP]: 'WhatsApp',
  [INBOX_TYPES.WEB]: 'Website',
  [INBOX_TYPES.EMAIL]: 'Email',
  [INBOX_TYPES.TELEGRAM]: 'Telegram',
  [INBOX_TYPES.TIKTOK]: 'TikTok',
};

const idLabelFor = channelType => {
  if (channelType === INBOX_TYPES.INSTAGRAM) return t('CONTACT_PANEL.INSTAGRAM_ID');
  if (channelType === INBOX_TYPES.WHATSAPP) return t('CONTACT_PANEL.WHATSAPP_ID');
  if (channelType === INBOX_TYPES.FB) return t('CONTACT_PANEL.MESSENGER_ID');
  return t('CONTACT_PANEL.IDENTIFIER');
};

const channelAccounts = computed(() => {
  const seen = new Set();
  const rows = (props.contactData?.contactInboxes || [])
    .map(item => {
      const channelType = item.inbox?.channelType;
      const sourceId = (item.sourceId || '').toString();
      if (!sourceId || seen.has(sourceId)) return null;
      seen.add(sourceId);
      return {
        key: `${item.inbox?.id || channelType}-${sourceId}`,
        label: CHANNEL_LABELS[channelType] || item.inbox?.name || 'Chat',
        inboxName: item.inbox?.name || '',
        idLabel: idLabelFor(channelType),
        sourceId,
      };
    })
    .filter(Boolean);

  const details = props.contactData?.additionalAttributes || {};
  const extras = [
    ['messenger', details.socialMessengerUserId, t('CONTACT_PANEL.MESSENGER_ID')],
    ['instagram', details.socialInstagramUserId, t('CONTACT_PANEL.INSTAGRAM_ID')],
    ['whatsapp', details.socialWhatsappUserId, t('CONTACT_PANEL.WHATSAPP_ID')],
  ];
  extras.forEach(([key, sourceId, idLabel]) => {
    const value = (sourceId || '').toString();
    if (!value || seen.has(value)) return;
    seen.add(value);
    rows.push({
      key,
      label: idLabel.replace(/ ID$| number$/, ''),
      inboxName: '',
      idLabel,
      sourceId: value,
    });
  });
  return rows;
});

const channelFacts = computed(() => {
  const details = props.contactData?.additionalAttributes || {};
  const facts = [];
  if (details.socialInstagramFollowerCount != null && details.socialInstagramFollowerCount !== '') {
    facts.push({
      key: 'followers',
      label: t('CONTACT_PANEL.FOLLOWERS'),
      value: String(details.socialInstagramFollowerCount),
    });
  }
  if (details.socialInstagramIsVerifiedUser) {
    facts.push({
      key: 'verified',
      label: t('CONTACT_PANEL.INSTAGRAM'),
      value: t('CONTACT_PANEL.VERIFIED'),
    });
  }
  if (details.socialInstagramIsUserFollowBusiness) {
    facts.push({
      key: 'follows',
      label: t('CONTACT_PANEL.INSTAGRAM'),
      value: t('CONTACT_PANEL.FOLLOWS_YOU'),
    });
  }
  const messengerName = [details.socialMessengerFirstName, details.socialMessengerLastName]
    .filter(Boolean)
    .join(' ');
  if (messengerName) {
    facts.push({
      key: 'messenger',
      label: t('CONTACT_PANEL.MESSENGER_NAME'),
      value: messengerName,
    });
  }
  if (details.socialMessengerLocale) {
    facts.push({
      key: 'locale',
      label: t('CONTACT_PANEL.LANGUAGE'),
      value: details.socialMessengerLocale,
    });
  }
  return facts;
});

const profileLinks = computed(() =>
  ['instagram', 'facebook']
    .map(network => {
      const handle = (state.additionalAttributes.socialProfiles?.[network] || '')
        .toString()
        .trim();
      if (!handle || handle.includes(' ')) return null;
      const url = socialProfileUrl(network, handle);
      return url ? { network, url } : null;
    })
    .filter(Boolean)
);

const socialProfilesForm = computed(() =>
  Object.entries(SOCIAL_CONFIG).map(([key, icon]) => ({
    key,
    placeholder: t(`CONTACTS_LAYOUT.CARD.SOCIAL_MEDIA.FORM.${key}.PLACEHOLDER`),
    icon,
  }))
);

const isValidationField = key => {
  const field = FORM_CONFIG[key]?.field;
  return ['firstName', 'email'].includes(field);
};

const getValidationKey = key => {
  return FORM_CONFIG[key]?.field;
};

// Creates a computed property for two-way form field binding
const getFormBinding = key => {
  const field = FORM_CONFIG[key]?.field;
  if (!field) return null;

  return computed({
    get: () => {
      // Handle firstName/lastName fields
      if (field === 'firstName' || field === 'lastName') {
        return state[field]?.toString() || '';
      }

      // Handle nested vs non-nested fields
      const [base, nested] = field.split('.');
      // Example: 'email' → state.email
      // Example: 'additionalAttributes.city' → state.additionalAttributes.city
      return (nested ? state[base][nested] : state[base])?.toString() || '';
    },

    set: async value => {
      // Handle name fields specially to maintain the combined 'name' field
      if (field === 'firstName' || field === 'lastName') {
        state[field] = value;
        // Example: firstName="John", lastName="Doe" → name="John Doe"
        state.name = `${state.firstName} ${state.lastName}`.trim();
      } else {
        // Handle nested vs non-nested fields
        const [base, nested] = field.split('.');
        if (nested) {
          // Example: additionalAttributes.city = "New York"
          state[base][nested] = value;
        } else {
          // Example: email = "test@example.com"
          state[base] = value;
        }
      }

      await emitContactUpdate();
    },
  });
};

const getMessageType = key => {
  return isValidationField(key) && v$.value[getValidationKey(key)]?.$error
    ? 'error'
    : 'info';
};

const handleCountrySelection = value => {
  const selectedCountry = countries.find(option => option.id === value);
  state.additionalAttributes.country = selectedCountry?.name || '';
  emit('update', state);
};

const handleCompanySelection = async ({ id, name }) => {
  state.companyId = id || '';
  state.additionalAttributes.companyName = name || '';
  await emitContactUpdate();
};

const handleSocialProfileInput = item => {
  const key = item.key.toLowerCase();
  if (key === 'whatsapp') {
    state.additionalAttributes.socialProfiles[key] = normalizeWhatsAppUsername(
      state.additionalAttributes.socialProfiles[key]
    );
  }
  emit('update', state);
};

const resetValidation = () => {
  v$.value.$reset();
};

const resetForm = () => {
  Object.assign(state, defaultState);
};

watch(
  () => [props.contactData?.id, props.contactData?.companyId],
  ([id]) => {
    if (id) prepareStateBasedOnProps();
  },
  { immediate: true }
);

// Expose state to parent component for avatar upload
defineExpose({
  state,
  resetValidation,
  isFormInvalid,
  resetForm,
});
</script>

<template>
  <div class="flex flex-col gap-6">
    <div class="flex flex-col items-start gap-2">
      <span class="py-1 text-sm font-medium text-n-slate-12">
        {{ t('CONTACTS_LAYOUT.CARD.EDIT_DETAILS_FORM.TITLE') }}
      </span>
      <div class="grid w-full grid-cols-1 gap-4 sm:grid-cols-2">
        <template v-for="item in editDetailsForm" :key="item.key">
          <ComboBox
            v-if="item.key === 'COUNTRY'"
            v-model="state.additionalAttributes.countryCode"
            :options="countryOptions"
            :placeholder="item.placeholder"
            class="[&>div>button]:h-8"
            :class="{
              '[&>div>button]:bg-n-alpha-black2 [&>div>button:not(.focused)]:!outline-transparent':
                !isDetailsView,
              '[&>div>button]:!bg-n-alpha-black2': isDetailsView,
            }"
            @update:model-value="handleCountrySelection"
          />
          <PhoneNumberInput
            v-else-if="item.key === 'PHONE_NUMBER'"
            v-model="getFormBinding(item.key).value"
            :placeholder="item.placeholder"
            :show-border="isDetailsView"
          />
          <div
            v-else-if="item.key === 'COMPANY_NAME' && hasCompaniesFeature"
            class="min-w-0 [&>div>div>button]:h-8"
          >
            <CompanySelector
              :model-value="state.companyId"
              :selected-name="state.additionalAttributes.companyName"
              :is-details-view="isDetailsView"
              @select="handleCompanySelection"
            />
          </div>
          <Input
            v-else
            v-model="getFormBinding(item.key).value"
            :placeholder="item.placeholder"
            :message-type="getMessageType(item.key)"
            :custom-input-class="`h-8 !pt-1 !pb-1 ${
              !isDetailsView
                ? '[&:not(.error,.focus)]:!outline-transparent'
                : ''
            }`"
            class="w-full"
            @input="
              isValidationField(item.key) &&
                v$[getValidationKey(item.key)].$touch()
            "
            @blur="
              isValidationField(item.key) &&
                v$[getValidationKey(item.key)].$touch()
            "
          />
        </template>
      </div>
    </div>
    <div class="flex flex-col items-start gap-2">
      <span class="py-1 text-sm font-medium text-n-slate-12">
        {{ t('CONTACTS_LAYOUT.CARD.SOCIAL_MEDIA.TITLE') }}
      </span>
      <div v-if="channelAccounts.length" class="flex flex-col gap-2">
        <p
          v-for="account in channelAccounts"
          :key="account.key"
          class="mb-0 text-sm text-n-slate-11"
        >
          <span class="font-medium text-n-slate-12">
            {{ t('CONTACT_PANEL.TEXTED_FROM') }}:
          </span>
          {{ account.label }}
          <span v-if="account.inboxName">· {{ account.inboxName }}</span>
          <br />
          <span class="font-medium text-n-slate-12">{{ account.idLabel }}:</span>
          {{ account.sourceId }}
        </p>
      </div>
      <div v-if="profileLinks.length" class="flex flex-col gap-1">
        <a
          v-for="link in profileLinks"
          :key="link.network"
          :href="link.url"
          target="_blank"
          rel="noopener noreferrer"
          class="text-sm underline text-n-slate-12"
        >
          {{ link.url }}
        </a>
      </div>
      <div v-if="channelFacts.length" class="flex flex-col gap-1">
        <p
          v-for="fact in channelFacts"
          :key="fact.key"
          class="mb-0 text-sm text-n-slate-11"
        >
          <span class="font-medium text-n-slate-12">{{ fact.label }}:</span>
          {{ fact.value }}
        </p>
      </div>
      <div class="flex flex-wrap gap-2">
        <div
          v-for="item in socialProfilesForm"
          :key="item.key"
          class="flex items-center h-8 gap-2 px-2 rounded-lg"
          :class="{
            'bg-n-alpha-2 dark:bg-n-solid-2': isDetailsView,
            'bg-n-alpha-2 dark:bg-n-solid-3': !isDetailsView,
          }"
        >
          <Icon
            :icon="item.icon"
            class="flex-shrink-0 text-n-slate-11 size-4"
          />
          <input
            v-model="
              state.additionalAttributes.socialProfiles[item.key.toLowerCase()]
            "
            class="w-auto min-w-[100px] text-sm bg-transparent outline-none reset-base text-n-slate-12 dark:text-n-slate-12 placeholder:text-n-slate-10 dark:placeholder:text-n-slate-10"
            :placeholder="item.placeholder"
            :size="
              Math.max(
                String(
                  state.additionalAttributes.socialProfiles[
                    item.key.toLowerCase()
                  ] || item.placeholder
                ).length,
                12
              )
            "
            @input="handleSocialProfileInput(item)"
          />
        </div>
      </div>
    </div>
  </div>
</template>
