import React, { useCallback, useEffect, useMemo, useState } from "react";
import {
  OrganizationPage_OrganizationFragment,
  useDeleteOrganizationMutation,
  useUpdateOrganizationMutation,
} from "@app/graphql";
import { extractError, formItemLayout, tailFormItemLayout } from "@app/lib";
import * as Sentry from "@sentry/react";
import { Alert, Button, Form, Input, message, Popconfirm } from "antd";
import { useForm } from "antd/lib/form/Form";
import Router, { useRouter } from "next/router";
import useTranslation from "next-translate/useTranslation";
import { Store } from "rc-field-form/lib/interface";

import { Redirect } from "./index";

interface UpdateOrganizationFormProps {
  organization: OrganizationPage_OrganizationFragment;
}

export const UpdateOrganizationForm: React.FC<UpdateOrganizationFormProps> = ({
  organization,
}) => {
  const { id: organizationId, name, slug } = organization;
  const initialValues = useMemo(
    () => ({
      slug,
      name,
    }),
    [name, slug]
  );

  const { t } = useTranslation("admin");
  const [form] = useForm();
  const router = useRouter();
  const [updateOrganization] = useUpdateOrganizationMutation();
  const [error, setError] = useState<Error | null>(null);
  const [deleteOrganization] = useDeleteOrganizationMutation();
  const [deleting, setDeleting] = useState(false);

  useEffect(() => {
    // Set form initialValues if they have changed after the initial rendering
    form.setFieldsValue(initialValues);
  }, [form, initialValues]);

  const handleDelete = useCallback(async () => {
    try {
      setDeleting(true);
      await deleteOrganization({
        variables: {
          organizationId,
        },
        refetchQueries: ["SharedLayout"],
      });
      message.info(`Organization '${name}' successfully deleted`);
      router.push("/");
    } catch (e) {
      setError(e);
      Sentry.captureException(e);
    }
    setDeleting(false);
  }, [deleteOrganization, organizationId, name, router]);

  const handleSubmit = useCallback(
    async (values: Store) => {
      try {
        setError(null);
        const { data } = await updateOrganization({
          variables: {
            input: {
              id: organizationId,
              patch: { slug: values.slug, name: values.name },
            },
          },
        });
        message.success("Organization updated");
        const newSlug = data?.updateOrganization?.organization?.slug;
        if (newSlug && newSlug !== slug) {
          Router.push(
            "/admin/organization/[slug]/settings",
            `/admin/organization/${newSlug}/settings`
          );
        }
      } catch (e) {
        setError(e);
        Sentry.captureException(e);
      }
    },
    [organizationId, slug, updateOrganization]
  );

  if (!organization.currentUserIsOwner) {
    return (
      <Redirect
        as={`/admin/organization/${slug}`}
        href="/admin/organization/[slug]"
      />
    );
  }

  return (
    <Form
      {...formItemLayout}
      form={form}
      initialValues={initialValues}
      onFinish={handleSubmit}
    >
      <Form.Item
        label={t("organizations.forms.labels.name")}
        name="name"
        rules={[
          { required: true, message: "Organization name is required" },
          { min: 1, message: "Organization name must not be empty" },
        ]}
      >
        <Input />
      </Form.Item>
      <Form.Item
        label={t("organizations.forms.labels.slug")}
        name="slug"
        rules={[
          { required: true, message: "Slug is required" },
          { min: 2, message: "Slug must be at least 2 characters long" },
        ]}
      >
        <Input />
      </Form.Item>
      {error && (
        <Form.Item>
          <Alert
            description={<span>{extractError(error).message}</span>}
            message={`Updating organization`}
            type="error"
          />
        </Form.Item>
      )}
      <Form.Item {...tailFormItemLayout}>
        <Button htmlType="submit">
          {t("organizations.updateOrganization")}
        </Button>
        <Popconfirm
          cancelText={t("common:no")}
          okText={t("common:yes")}
          title={t("organizations.deleteOrganizationConfirmText")}
          onConfirm={handleDelete}
        >
          <Button
            data-cy="eventregistrationform-button-delete-registration"
            loading={deleting}
            style={{ marginLeft: 5 }}
            danger
          >
            {t("organizations.deleteOrganization")}
          </Button>
        </Popconfirm>
      </Form.Item>
    </Form>
  );
};
