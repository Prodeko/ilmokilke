import React, { useCallback, useEffect, useState } from "react";
import { ApolloError, useApolloClient } from "@apollo/client";
import {
  CreateEventCategoryPageQuery,
  UpdateEventCategoryPageQuery,
  useCreateEventCategoryMutation,
  useUpdateEventCategoryMutation,
} from "@app/graphql";
import {
  extractError,
  formItemLayout,
  getCodeFromError,
  tailFormItemLayout,
} from "@app/lib";
import * as Sentry from "@sentry/react";
import { Alert, Button, Form, Input, Select } from "antd";
import { useRouter } from "next/router";
import useTranslation from "next-translate/useTranslation";

const { Option } = Select;

interface EventCategoryFormProps {
  type: "update" | "create";
  data: CreateEventCategoryPageQuery | UpdateEventCategoryPageQuery;
  formRedirect: { pathname: string; query: { [key: string]: string } } | string;
  // categoryId and initialValues are used when type is "update"
  // i.e. we are updating an existing event category
  categoryId?: string;
  initialValues?: any;
}

export const EventCategoryForm = ({
  type,
  data,
  formRedirect,
  categoryId,
  initialValues,
}: EventCategoryFormProps) => {
  const { supportedLanguages } = data?.languages || {};
  const { organizationMemberships } = data?.currentUser || {};

  // Translations, router, apollo
  const { t } = useTranslation("events");
  const router = useRouter();
  const client = useApolloClient();

  // Handling form values, errors and submission
  const [form] = Form.useForm();
  const [formSubmitting, setFormSubmimtting] = useState(false);
  const [formError, setFormError] = useState<Error | ApolloError | null>(null);
  const [selectedLanguages, setSelectedLanguages] = useState(
    supportedLanguages || []
  );

  // Mutations
  const [updateEventCategory] = useUpdateEventCategoryMutation();
  const [createEventCategory] = useCreateEventCategoryMutation();

  useEffect(() => {
    // Set form initialValues if they have changed after the initial rendering
    form.setFieldsValue(initialValues);
  }, [form, initialValues]);

  useEffect(() => {
    // Set selected languages if supportedLanguages change
    if (supportedLanguages) {
      setSelectedLanguages(supportedLanguages);
    }
  }, [supportedLanguages]);

  const handleSubmit = useCallback(
    async (values) => {
      setFormSubmimtting(true);
      setFormError(null);
      try {
        if (type === "create") {
          await createEventCategory({
            variables: {
              ...values,
            },
          });
        } else if (type === "update") {
          await updateEventCategory({
            variables: {
              ...values,
              id: categoryId,
            },
          });
        }

        client.resetStore();
        setFormError(null);
        router.push(formRedirect, formRedirect);
      } catch (e) {
        setFormError(e);
        Sentry.captureException(e);
      }
      setFormSubmimtting(false);
    },
    [
      createEventCategory,
      updateEventCategory,
      categoryId,
      client,
      formRedirect,
      router,
      type,
    ]
  );

  const code = getCodeFromError(formError);

  return (
    <Form
      {...formItemLayout}
      form={form}
      initialValues={{ languages: selectedLanguages, ...initialValues }}
      onFinish={handleSubmit}
    >
      <Form.Item
        label={t("languages")}
        name="languages"
        rules={[
          {
            required: true,
            message: t("forms.rules.provideLanguage"),
            type: "array",
          },
        ]}
      >
        <Select
          data-cy="eventcategoryform-select-language"
          mode="multiple"
          placeholder={t("forms.placeholders.languages")}
          allowClear
          onChange={(e) => setSelectedLanguages(e as string[])}
        >
          {supportedLanguages?.map((l, i) => (
            <Option
              key={i}
              data-cy={`eventcategoryform-select-language-option-${l}`}
              value={l ? l : ""}
            >
              {t(`common:${l}`)}
            </Option>
          ))}
        </Select>
      </Form.Item>
      <Form.Item
        label={t("organizer")}
        name="ownerOrganization"
        rules={[
          {
            required: true,
            message: t("forms.rules.eventCategory.provideOrganizer"),
          },
        ]}
      >
        <Select
          data-cy="eventcategoryform-select-organization-id"
          placeholder={t("forms.placeholders.eventCategory.organizer")}
        >
          {organizationMemberships?.nodes?.map((o) => (
            <Option key={o.organization?.id} value={o.organization?.id!}>
              {o.organization?.name}
            </Option>
          ))}
        </Select>
      </Form.Item>
      <Form.Item label={t("common:name")}>
        <Input.Group compact>
          {selectedLanguages.length === 0 ? (
            <Form.Item noStyle>
              <Input disabled />
            </Form.Item>
          ) : (
            selectedLanguages.map((l, i) => (
              <Form.Item
                key={l}
                name={["name", l!]}
                rules={[
                  {
                    required: true,
                    message: t("forms.rules.eventCategory.provideName"),
                  },
                ]}
                noStyle
              >
                <Input
                  data-cy={`eventcategoryform-input-name-${l}`}
                  placeholder={t(`forms.placeholders.${l}`)}
                  style={i > 0 ? { marginTop: 5 } : undefined}
                />
              </Form.Item>
            ))
          )}
        </Input.Group>
      </Form.Item>
      <Form.Item label={t("common:shortDescription")}>
        <Input.Group compact>
          {selectedLanguages.length === 0 ? (
            <Form.Item noStyle>
              <Input.TextArea disabled />
            </Form.Item>
          ) : (
            selectedLanguages.map((l, i) => (
              <Form.Item
                key={l}
                name={["description", l!]}
                rules={[
                  {
                    required: true,
                    message: t("forms.rules.eventCategory.provideDescription"),
                  },
                ]}
                noStyle
              >
                <Input.TextArea
                  data-cy={`eventcategoryform-input-description-${l}`}
                  placeholder={t(`forms.placeholders.${l}`)}
                  style={i > 0 ? { marginTop: 5 } : undefined}
                />
              </Form.Item>
            ))
          )}
        </Input.Group>
      </Form.Item>
      {formError && (
        <Form.Item {...tailFormItemLayout}>
          <Alert
            description={
              <span>
                {extractError(formError).message}
                {code && (
                  <span>
                    ({t("error:errorCode")}: <code>ERR_{code}</code>)
                  </span>
                )}
              </span>
            }
            message={t("errors.eventCategoryCreationFailed")}
            type="error"
          />
        </Form.Item>
      )}
      <Form.Item {...tailFormItemLayout}>
        <Button
          data-cy="eventcategoryform-button-create"
          disabled={selectedLanguages.length === 0 ? true : false}
          htmlType="submit"
          loading={formSubmitting}
          type="primary"
        >
          {t(`common:${type}`)}
        </Button>
      </Form.Item>
    </Form>
  );
};
