import React from "react";
import { AdminLayout, ErrorAlert, Redirect, SpinPadded } from "@app/components";
import { useSharedQuery } from "@app/graphql";
import { PageHeader } from "antd";
import { NextPage } from "next";

const Admin_Main: NextPage = () => {
  const query = useSharedQuery();
  const { data, loading, error } = query;

  return (
    <AdminLayout href="/admin" query={query}>
      {data && data.currentUser ? (
        <PageHeader title="Edit profile" />
      ) : loading ? (
        <SpinPadded />
      ) : error ? (
        <ErrorAlert error={error} />
      ) : (
        <Redirect href={`/login?next=${encodeURIComponent("/settings")}`} />
      )}
    </AdminLayout>
  );
};

export default Admin_Main;
