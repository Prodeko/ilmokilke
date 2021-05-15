import React from "react";
import {
  AdminLayout,
  EventCategoryForm,
  Redirect,
  useQueryId,
} from "@app/components";
import { useUpdateEventCategoryPageQuery } from "@app/graphql";
import { filterObjectByKeys } from "@app/lib";
import { Col, PageHeader, Row } from "antd";
import { NextPage } from "next";
import { useRouter } from "next/router";
import useTranslation from "next-translate/useTranslation";

type UpdateFormInitialValues = {
  name: string;
  description: string;
};

function constructInitialValues(values: any) {
  const filteredValues = filterObjectByKeys(values, [
    "name",
    "description",
  ]) as UpdateFormInitialValues;

  return {
    ...filteredValues,
    ownerOrganizationId: values?.ownerOrganization?.id,
  };
}

const Admin_UpdateEventCategory: NextPage = () => {
  const { t } = useTranslation("events");
  const router = useRouter();
  const categoryId = useQueryId();
  const query = useUpdateEventCategoryPageQuery({
    variables: { id: categoryId },
  });
  const { loading, error } = query;
  const eventCategory = query?.data?.eventCategory;

  // If event category is not found redirect to index
  if (!loading && !error && !eventCategory) {
    return <Redirect href="/" layout />;
  }

  // Redirect to index if the user is not part of any organization
  const organizationMemberships =
    query?.data?.currentUser?.organizationMemberships?.totalCount;
  if (organizationMemberships <= 0) {
    return <Redirect href="/" layout />;
  }

  return (
    <AdminLayout href={`/admin/event-category/${categoryId}`} query={query}>
      <Row>
        <Col flex={1}>
          <PageHeader
            title={t("createEventCategory.title")}
            onBack={() => router.push("/admin/event-category/list")}
          />
          <EventCategoryForm
            categoryId={categoryId}
            data={query.data}
            formRedirect="/admin/event-category/list"
            initialValues={constructInitialValues(eventCategory)}
            type="update"
          />
        </Col>
      </Row>
    </AdminLayout>
  );
};

export default Admin_UpdateEventCategory;
