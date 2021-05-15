import React, { useState } from "react";
import {
  AdminLayout,
  ORGANIZATION_RESULTS_PER_PAGE,
  OrganizationMembers,
  UpdateOrganizationForm,
  useOrganizationLoading,
  useQuerySlug,
} from "@app/components";
import {
  OrganizationPage_OrganizationFragment,
  useOrganizationPageQuery,
} from "@app/graphql";
import { Col, PageHeader, Row } from "antd";
import { NextPage } from "next";

const Admin_Organizations: NextPage = () => {
  const slug = useQuerySlug();
  const [page, setPage] = useState(1);
  const query = useOrganizationPageQuery({
    variables: { slug, offset: (page - 1) * ORGANIZATION_RESULTS_PER_PAGE },
  });
  const organizationLoadingElement = useOrganizationLoading(query);
  const organization = query?.data?.organizationBySlug;

  const props = { page, setPage };

  return (
    <AdminLayout href="/admin/organization/[slug]" query={query}>
      {organizationLoadingElement || (
        <OrganizationPageInner organization={organization!} {...props} />
      )}
    </AdminLayout>
  );
};

interface OrganizationPageInnerProps {
  organization: OrganizationPage_OrganizationFragment;
  page: number;
  setPage: React.Dispatch<React.SetStateAction<number>>;
}

const OrganizationPageInner: React.FC<OrganizationPageInnerProps> = (props) => {
  const { organization, ...rest } = props;

  return (
    <Row>
      <Col flex={1}>
        <PageHeader title={organization.name} />
        <UpdateOrganizationForm organization={organization} />
        <OrganizationMembers organization={organization} {...rest} />
      </Col>
    </Row>
  );
};

export default Admin_Organizations;
