import React, { useCallback, useEffect, useMemo, useState } from "react";
import { DndProvider } from "react-dnd";
import { HTML5Backend } from "react-dnd-html5-backend";
import DragOutlined from "@ant-design/icons/DragOutlined";
import MinusCircleTwoTone from "@ant-design/icons/MinusCircleTwoTone";
import PlusOutlined from "@ant-design/icons/PlusOutlined";
import {
  ApolloError,
  DocumentNode,
  useApolloClient,
  useMutation,
} from "@apollo/client";
import {
  CreateEventPageQuery,
  Quota,
  UpdateEventPageQuery,
  useRenderEmailTemplateQuery,
} from "@app/graphql";
import {
  extractError,
  filterObjectByKeys,
  formItemLayout,
  getCodeFromError,
  tailFormItemLayout,
} from "@app/lib";
import * as Sentry from "@sentry/react";
import {
  Alert,
  Badge,
  Button,
  Card,
  Col,
  DatePicker,
  Form,
  Input,
  InputNumber,
  Row,
  Select,
  Space,
  Switch,
  Tabs,
  Tooltip,
  Typography,
} from "antd";
import dayjs from "dayjs";
import { debounce, uniq } from "lodash";
import { useRouter } from "next/router";
import useTranslation from "next-translate/useTranslation";
import slugify from "slugify";

import { DisableDraggable, Draggable } from "./Draggable";
import { FileUpload } from "./index";

const { Text } = Typography;
const { Option } = Select;
const { TabPane } = Tabs;
const { TextArea, Group } = Input;
const { RangePicker } = DatePicker;

type TranslatedFormValue = {
  fi: string;
  en: string;
};

type FormValues = {
  languages: string[];
  ownerOrganizationId: string;
  categoryId: string;
  name: TranslatedFormValue;
  description: TranslatedFormValue;
  eventTime: Date[];
  registrationTime: Date[];
  isHighlighted: boolean;
  headerImageFile: string;
  isDraft: boolean;
  quotas: Quota[];
};

interface EventFormProps {
  type: "update" | "create";
  formRedirect: string;
  data: CreateEventPageQuery | UpdateEventPageQuery;
  eventMutationDocument: DocumentNode;
  quotasMutationDocument: DocumentNode;
  // eventId and initialValues are only used when type is "update"
  // i.e. we are updating an existing event
  eventId?: string;
  initialValues?: any;
}

function getFormattedEventTime(dates?: Date[]) {
  const formatString = "D.M.YY HH:mm";
  const eventStartTime = dayjs(dates?.[0]).format(formatString);
  const eventEndTime = dayjs(dates?.[1]).format(formatString);
  return `${eventStartTime} - ${eventEndTime}`;
}

function getEventSlug(name?: TranslatedFormValue, dates?: Date[]) {
  const eventStartTime = dates?.[0].toISOString();

  const daySlug = dayjs(eventStartTime).format("YYYY-M-D");
  const slug = slugify(`${daySlug}-${name?.["fi"]}`, {
    lower: true,
  });

  return name?.fi ? slug : "";
}

export const EventForm: React.FC<EventFormProps> = (props) => {
  const {
    formRedirect,
    data,
    initialValues,
    eventMutationDocument,
    quotasMutationDocument,
    type,
    eventId,
  } = props;
  const { supportedLanguages } = data?.languages || {};

  // Translations, router, apollo
  const { t, lang } = useTranslation("events");
  const router = useRouter();
  const client = useApolloClient();

  // Handling form values, errors and submission
  const [form] = Form.useForm();
  const [formSubmitting, setFormSubmimtting] = useState(false);
  const [formValues, setFormValues] = useState<FormValues | undefined>();
  const [formError, setFormError] = useState<Error | ApolloError | null>(null);
  const [quotaErrors, setQuotaErrors] = useState<any[] | null>(null);
  const [isDraft, setIsDraft] = useState(
    type === "create" || initialValues.isDraft
  );
  const [selectedLanguages, setSelectedLanguages] = useState(
    supportedLanguages || []
  );

  // Mutations
  const [eventQuery] = useMutation(eventMutationDocument, {
    context: { hasUpload: true },
  });
  const [quotasQuery] = useMutation(quotasMutationDocument);

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

  const code = getCodeFromError(formError);

  // For rendering email tab
  const [showHtml, setShowHtml] = useState(true);
  const {
    loading: templatesLoading,
    data: emailTemplatesData,
  } = useRenderEmailTemplateQuery({
    variables: {
      template: "event_registration.mjml.njk",
      variables: {
        registrationName: "{{ registrationName }}",
        registrationQuota: {
          fi: "{{ registrationQuota }}",
          en: "{{ registrationQuota }}",
        },
        eventName: formValues?.name,
        eventTime: getFormattedEventTime(formValues?.eventTime) || "",
        eventSlug: getEventSlug(formValues?.name, formValues?.eventTime),
        eventRegistrationUpdateLink: "{{ eventRegistrationUpdateLink }}",
      },
    },
  });

  const handleSubmit = useCallback(
    async (values) => {
      setFormSubmimtting(true);
      setFormError(null);
      setQuotaErrors(null);
      try {
        const {
          eventTime,
          registrationTime,
          name,
          headerImageFile: headerFile,
          quotas: valueQuotas,
        } = values;

        if (!valueQuotas) {
          throw new Error(t("errors.mustProvideEventQuota"));
        }

        const eventStartTime = eventTime[0].toISOString();
        const eventEndTime = eventTime[1].toISOString();

        const registrationStartTime = registrationTime[0].toISOString();
        const registrationEndTime = registrationTime[1].toISOString();

        const slug = getEventSlug(name, eventTime);
        const headerImageFile = headerFile?.originFileObj;

        // eventId is only used in update mutation
        const { data } = await eventQuery({
          variables: {
            ...values,
            slug,
            eventStartTime,
            eventEndTime,
            registrationStartTime,
            registrationEndTime,
            headerImageFile,
            eventId,
          },
        });
        const accessor = type === "create" ? "createEvent" : "updateEvent";
        const createdEventId = data[accessor].event.id;
        const quotas = valueQuotas.map((q: Quota, index: number) => {
          // Set quota position
          q.position = index;
          return filterObjectByKeys(q, ["id", "position", "title", "size"]);
        });
        // Run quotas query
        quotasQuery({
          variables: { input: { eventId: createdEventId, quotas } },
        });

        client.resetStore();
        setFormError(null);
        router.push(formRedirect, formRedirect);
      } catch (e) {
        setFormError(e);
        Sentry.captureException(e);
      }
      setFormSubmimtting(false);
    },
    [eventQuery, quotasQuery, client, formRedirect, router, t, type, eventId]
  );

  const debouncedSetFormValues = useMemo(
    () => debounce((newValues) => setFormValues(newValues), 500),
    []
  );

  const handleValuesChange = useCallback(
    async (_changedValues, allValues) => {
      debouncedSetFormValues(allValues);
    },
    [debouncedSetFormValues]
  );

  const debounceSetQuotaErrors = useMemo(
    () =>
      debounce(() => {
        let quotaErrors = form
          .getFieldsError()
          .filter((e) => e && e?.name[0] === "quotas" && e?.errors.length > 0)
          .map((e) => e?.errors[0])
          .filter((e) => !!e);
        return quotaErrors.length > 0 && setQuotaErrors(uniq(quotaErrors));
      }, 500),
    [form]
  );

  const handleFieldsChange = useCallback(async () => {
    // Filters form errors that relate to quotas in order to
    // display them on the general tab
    debounceSetQuotaErrors();
  }, [debounceSetQuotaErrors]);

  return (
    <Form
      {...formItemLayout}
      form={form}
      initialValues={{ languages: selectedLanguages, ...initialValues }}
      onFieldsChange={handleFieldsChange}
      onFinish={handleSubmit}
      onValuesChange={handleValuesChange}
    >
      <Tabs
        defaultActiveKey="general"
        tabBarExtraContent={{
          right: (
            <Badge
              color={isDraft ? "yellow" : "green"}
              text={isDraft ? t("forms.isDraft") : t("forms.isNotDraft")}
            />
          ),
        }}
      >
        <TabPane
          key="general"
          data-cy="eventform-tab-general"
          tab={t("forms.tabs.generalInfo")}
          forceRender
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
              data-cy="eventform-select-language"
              mode="multiple"
              placeholder={t("forms.placeholders.languages")}
              allowClear
              onChange={(e) => setSelectedLanguages(e as string[])}
            >
              {supportedLanguages?.map((l, i) => (
                <Option
                  key={i}
                  data-cy={`eventform-select-language-option-${l}`}
                  value={l ? l : ""}
                >
                  {t(`common:${l}`)}
                </Option>
              ))}
            </Select>
          </Form.Item>
          <Form.Item
            label={t("organizer")}
            name="ownerOrganizationId"
            rules={[
              {
                required: true,
                message: t("forms.rules.event.provideOrganizer"),
              },
            ]}
          >
            <Select
              data-cy="eventform-select-organization-id"
              placeholder={t("forms.placeholders.event.organizer")}
            >
              {data?.currentUser?.organizationMemberships?.nodes?.map(
                (o, i) => (
                  <Option
                    key={o.organization?.id}
                    data-cy={`eventform-select-organization-id-option-${i}`}
                    value={o.organization?.id}
                  >
                    {o.organization?.name}
                  </Option>
                )
              )}
            </Select>
          </Form.Item>
          <Form.Item
            label={t("category")}
            name="categoryId"
            rules={[
              {
                required: true,
                message: t("forms.rules.event.provideCategory"),
              },
            ]}
          >
            <Select
              data-cy="eventform-select-category-id"
              placeholder={t("forms.placeholders.event.category")}
            >
              {
                // @ts-ignore
                data?.eventCategories?.nodes?.map((a, i) => (
                  <Option
                    key={a.id}
                    data-cy={`eventform-select-category-id-option-${i}`}
                    value={a.id}
                  >
                    {a.name[lang]}
                  </Option>
                ))
              }
            </Select>
          </Form.Item>
          <Form.Item label={t("common:name")}>
            <Group compact>
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
                        message: t("forms.rules.event.provideName"),
                      },
                    ]}
                    noStyle
                  >
                    <Input
                      data-cy={`eventform-input-name-${l}`}
                      placeholder={t(`forms.placeholders.${l}`)}
                      style={i > 0 ? { marginTop: 5 } : undefined}
                    />
                  </Form.Item>
                ))
              )}
            </Group>
          </Form.Item>
          <Form.Item label={t("common:description")}>
            <Group compact>
              {selectedLanguages.length === 0 ? (
                <Form.Item noStyle>
                  <TextArea disabled />
                </Form.Item>
              ) : (
                selectedLanguages.map((l, i) => (
                  <Form.Item
                    key={l}
                    name={["description", l!]}
                    rules={[
                      {
                        required: true,
                        message: t("forms.rules.event.provideDescription"),
                      },
                    ]}
                    noStyle
                  >
                    <TextArea
                      data-cy={`eventform-input-description-${l}`}
                      placeholder={t(`forms.placeholders.${l}`)}
                      style={i > 0 ? { marginTop: 5 } : undefined}
                    />
                  </Form.Item>
                ))
              )}
            </Group>
          </Form.Item>
          <Form.Item
            label={t("forms.eventTime")}
            name="eventTime"
            rules={[
              {
                type: "array",
                required: true,
                message: t("forms.rules.event.provideEventTime"),
              },
            ]}
          >
            <RangePicker
              data-cy="eventform-input-event-time"
              format="YYYY-MM-DD HH:mm"
              showTime
            />
          </Form.Item>
          <Form.Item
            label={t("forms.registrationTime")}
            name="registrationTime"
            rules={[
              {
                type: "array",
                required: true,
                message: t("forms.rules.event.provideRegistrationTime"),
              },
            ]}
          >
            <RangePicker
              data-cy="eventform-input-registration-time"
              format="YYYY-MM-DD HH:mm"
              showTime
            />
          </Form.Item>
          <Form.Item
            label={t("forms.highlightEvent")}
            name="isHighlighted"
            valuePropName="checked"
          >
            <Switch data-cy="eventform-switch-highlight" />
          </Form.Item>
          <Form.Item
            getValueFromEvent={(e) => e[0]}
            label={t("headerImage")}
            name="headerImageFile"
            valuePropName="headerImageFile"
          >
            <FileUpload
              accept="image/*"
              cropAspect={851 / 315}
              data-cy="eventform-header-image-upload"
              maxCount={1}
            />
          </Form.Item>
          <Form.Item
            label={t("forms.saveAsDraft")}
            name="isDraft"
            valuePropName="checked"
          >
            <Switch
              data-cy="eventform-switch-save-as-draft"
              defaultChecked={isDraft}
              onChange={(checked) => setIsDraft(checked)}
            />
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
                message={t("errors.eventCreationFailed")}
                type="error"
              />
            </Form.Item>
          )}
          {quotaErrors ? (
            <Form.Item label={t("errors.otherFormErrors")}>
              {quotaErrors?.map((e, i) => (
                <div key={i} className="ant-form-text" style={{ color: "red" }}>
                  {e}
                </div>
              ))}
            </Form.Item>
          ) : null}
          <Form.Item {...tailFormItemLayout}>
            <Button
              data-cy="eventform-button-submit"
              disabled={selectedLanguages.length === 0 ? true : false}
              htmlType="submit"
              loading={formSubmitting}
            >
              {t(`common:${type}`)}
            </Button>
          </Form.Item>
        </TabPane>
        <TabPane
          key="quotas"
          data-cy="eventform-tab-quotas"
          tab={t("forms.tabs.quotas")}
          forceRender
        >
          <DndProvider backend={HTML5Backend}>
            <Form.List
              name="quotas"
              rules={[
                {
                  validator: async (_, quotas) => {
                    if (!quotas || quotas.length < 1) {
                      return Promise.reject(
                        new Error(t("errors.mustProvideEventQuota"))
                      );
                    }
                  },
                },
              ]}
            >
              {(fields, { add, remove, move }) => (
                <>
                  {fields.map((field, index) => {
                    const { name, fieldKey } = field;
                    const numRegistrations =
                      initialValues?.quotas[fieldKey]?.registrations
                        ?.totalCount || 0;
                    return (
                      <Draggable
                        {...field}
                        key={field.key}
                        id={field.key}
                        index={index}
                        move={move}
                      >
                        <Form.Item
                          fieldKey={[fieldKey, "position"]}
                          name={[name, "position"]}
                          required={true}
                          noStyle
                        >
                          <Input type="hidden" />
                        </Form.Item>
                        <Form.Item
                          fieldKey={[fieldKey, "id"]}
                          name={[name, "id"]}
                          required={false}
                          noStyle
                        >
                          <Input type="hidden" />
                        </Form.Item>
                        <Space
                          align="baseline"
                          style={{ display: "flex", marginBottom: 8 }}
                        >
                          <DragOutlined />
                          {selectedLanguages.map((l) => (
                            <div key={l}>
                              <Form.Item
                                key={`${name}-${l}`}
                                fieldKey={[fieldKey, "title", l!]}
                                name={[name, "title", l!]}
                                rules={[
                                  {
                                    required: true,
                                    message: t(
                                      "forms.rules.quota.provideQuotaTitle"
                                    ),
                                  },
                                ]}
                                noStyle
                              >
                                <Input
                                  data-cy={`eventform-input-quotas-title-${l}-${fieldKey}`}
                                  draggable={false}
                                  placeholder={`${t(
                                    "forms.placeholders.quota.title"
                                  )} ${t(
                                    `forms.placeholders.${l}`
                                  ).toLowerCase()}`}
                                  onDragStart={(event) => {
                                    event.stopPropagation();
                                    event.preventDefault();
                                  }}
                                />
                              </Form.Item>
                            </div>
                          ))}
                          <Form.Item
                            fieldKey={[fieldKey, "size"]}
                            name={[name, "size"]}
                            rules={[
                              {
                                required: true,
                                message: t(
                                  "forms.rules.quota.provideQuotaSize"
                                ),
                              },
                            ]}
                            noStyle
                          >
                            <InputNumber
                              {...DisableDraggable}
                              data-cy={`eventform-input-quotas-size-${fieldKey}`}
                              min={1}
                              placeholder={t("forms.placeholders.quota.size")}
                            />
                          </Form.Item>
                          {numRegistrations === 0 ? (
                            <Tooltip title={t("removeQuota")}>
                              <MinusCircleTwoTone
                                {...DisableDraggable}
                                twoToneColor="red"
                                onClick={() => remove(name)}
                              />
                            </Tooltip>
                          ) : (
                            <div>
                              {t("numRegistrations")}: {numRegistrations}
                            </div>
                          )}
                        </Space>
                      </Draggable>
                    );
                  })}
                  <Form.Item>
                    <Button
                      data-cy="eventform-quotas-add-quota"
                      icon={<PlusOutlined />}
                      type="dashed"
                      block
                      onClick={() => add()}
                    >
                      {t("addQuota")}
                    </Button>
                  </Form.Item>
                </>
              )}
            </Form.List>
          </DndProvider>
        </TabPane>
        <TabPane
          key="email"
          data-cy="eventform-tab-email"
          tab={t("forms.tabs.email")}
        >
          <Row>
            <Col span={24}>
              <Switch
                loading={templatesLoading}
                style={{ margin: 10 }}
                defaultChecked
                onChange={(checked) => setShowHtml(checked)}
              />
              <Text>{t("common:emailSwitchLabel")}</Text>
              <Card loading={templatesLoading} style={{ marginLeft: 10 }}>
                {showHtml ? (
                  <div
                    dangerouslySetInnerHTML={{
                      __html: emailTemplatesData?.renderEmailTemplate?.html!,
                    }}
                  />
                ) : (
                  <Text style={{ whiteSpace: "pre-wrap" }}>
                    {emailTemplatesData?.renderEmailTemplate?.text}
                  </Text>
                )}
              </Card>
            </Col>
          </Row>
        </TabPane>
      </Tabs>
    </Form>
  );
};
