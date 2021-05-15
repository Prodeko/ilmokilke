import React from "react";
import { AdminLayout, EventCategoryForm, Redirect } from "@app/components";
import { useCreateEventCategoryPageQuery } from "@app/graphql";
import { Col, PageHeader, Row } from "antd";
import { NextPage } from "next";
import { useRouter } from "next/dist/client/router";
import useTranslation from "next-translate/useTranslation";

const Admin_CreateEventCategory: NextPage = () => {
  const query = useCreateEventCategoryPageQuery();
  const { t } = useTranslation("events");
  const router = useRouter();

  // Redirect to index if the user is not part of any organization
  const organizationMemberships =
    query?.data?.currentUser?.organizationMemberships?.totalCount;
  if (organizationMemberships <= 0) {
    return <Redirect href="/" layout />;
  }

  return (
    <AdminLayout href={"/admin/event-category/create"} query={query}>
      <Row>
        <Col flex={1}>
          <PageHeader
            title={t("createEventCategory.title")}
            onBack={() => router.push("/admin/event-category/list")}
          />
          <EventCategoryForm
            data={query.data}
            formRedirect="/admin/event-category/list"
            type="create"
          />
        </Col>
      </Row>
    </AdminLayout>
  );
};

export default Admin_CreateEventCategory;
