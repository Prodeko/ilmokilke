import React, { useCallback, useState } from "react";
import { useApolloClient } from "@apollo/client";
import { Event, EventCategory } from "@app/graphql";
import * as Sentry from "@sentry/react";
import { Button, message, Popconfirm, Space } from "antd";
import useTranslation from "next-translate/useTranslation";

import { ButtonLink, ErrorBanner } from ".";

interface AdminTableActionsProps {
  adminUrl: string;
  bannerErrorText?: JSX.Element;
  dataType: Event | EventCategory;
  deleteMutation: any;
  deleteConfirmTranslate: string;
}

export const AdminTableActions: React.FC<AdminTableActionsProps> = ({
  adminUrl,
  bannerErrorText,
  dataType,
  deleteMutation,
  deleteConfirmTranslate,
}) => {
  const { t } = useTranslation("admin");
  const client = useApolloClient();
  const [deleteDataType] = deleteMutation();
  const [error, setError] = useState<Error | null>(null);

  const doDelete = useCallback(async () => {
    try {
      await deleteDataType({
        variables: { id: dataType?.id },
      });
      // Success: refetch
      client.resetStore();
      message.info(t("notifications.deleteSuccess"));
    } catch (e) {
      Sentry.captureException(e);
      setError(e);
    }
  }, [client, deleteDataType, dataType, t]);

  return (
    <>
      <Space>
        <ButtonLink
          as={`/admin/${adminUrl}/update/${dataType.id}`}
          href={`/admin/${adminUrl}/update/[id]`}
          type="primary"
        >
          <a>{t("common:update")}</a>
        </ButtonLink>
        <Popconfirm
          cancelText={t("common:no")}
          okText={t("common:yes")}
          placement="top"
          title={deleteConfirmTranslate}
          onConfirm={doDelete}
        >
          <Button
            data-cy="admin-table-delete-button"
            style={{ marginLeft: 5 }}
            danger
          >
            {t("common:delete")}
          </Button>
        </Popconfirm>
      </Space>
      {error ? (
        <ErrorBanner error={error} setError={setError}>
          {bannerErrorText}
        </ErrorBanner>
      ) : null}
    </>
  );
};
