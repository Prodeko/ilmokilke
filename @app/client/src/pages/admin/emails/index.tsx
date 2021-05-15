import React, { useState } from "react";
import { AdminLayout, ErrorAlert } from "@app/components";
import { useRenderEmailTemplatesQuery, useSharedQuery } from "@app/graphql";
import { Card, Col, PageHeader, Row, Switch, Typography } from "antd";
import { capitalize } from "lodash";
import { NextPage } from "next";
import useTranslation from "next-translate/useTranslation";

const { Text } = Typography;

const Admin_Emails: NextPage = () => {
  const { t } = useTranslation("admin");
  const query = useSharedQuery();
  const [showHtml, setShowHtml] = useState(true);
  const { loading, data, error } = useRenderEmailTemplatesQuery();

  return (
    <AdminLayout href="/admin/emails" query={query}>
      <PageHeader title="Emails" />
      {error ? (
        <ErrorAlert error={error} />
      ) : (
        <>
          <Switch
            loading={loading}
            style={{ marginRight: "1rem" }}
            defaultChecked
            onChange={(checked) => setShowHtml(checked)}
          />
          <Text>{t("common:emailSwitchLabel")}</Text>
          <Row gutter={16} style={{ marginTop: "1rem" }}>
            {data?.renderEmailTemplates.templates.map((email, i) => (
              <Col key={i} sm={{ span: 12 }} xs={{ span: 24 }}>
                <Card
                  loading={loading}
                  style={{ margin: "10px" }}
                  title={capitalize(email?.name)}
                >
                  {showHtml ? (
                    <div
                      dangerouslySetInnerHTML={{
                        __html: email?.html,
                      }}
                    />
                  ) : (
                    <Text style={{ whiteSpace: "pre-wrap" }}>{email.text}</Text>
                  )}
                </Card>
              </Col>
            ))}
          </Row>
        </>
      )}
    </AdminLayout>
  );
};

export default Admin_Emails;
